"""Golden model with probes: same arithmetic as src.golden (asserted), plus the decay inputs.

`ProbedHwModel.step` returns the same logits as `HwModel.step`; it re-runs `mamba_block`
from the golden primitives so it can also expose, per layer, p = FP16(dt * A') and dA.
Ablation (not hardware): `decay='float'` replaces the FP16 LUT dA by exact float 2^p in the
state update (FP32 product with the FP16 state), isolating the cost of the coarse dA.
"""
import numpy as np

from src.golden.arith.fp import F32, gemv, mul, value, writeback
from src.golden.net.layers import conv_silu, rmsnorm, scan_step
from src.golden.net.model import HwModel
from src.golden.arith.nlu import exp2, silu, softplus


def float_decay_scan(h, u, dt, B, C, L):
    """Ablation of `scan_step`: dA = 2^p exact (float64) instead of the FP16 LUT value."""
    dtu = value(mul(dt, u))
    dA = np.exp2(value(mul(dt[..., None], L['A2'])).astype(np.float64))
    acc = (dA * value(h)).astype(F32) + (dtu[..., None] * value(B)[..., None, :]).astype(F32)
    hn = writeback(acc.astype(F32))
    yacc = np.zeros(u.shape, F32)
    for n in range(h.shape[-1]):
        yacc = (yacc + value(C[..., n:n + 1]) * value(hn[..., n])).astype(F32)
    yacc = (yacc + value(L['D']) * value(u)).astype(F32)
    return hn, writeback(yacc)


def probed_block(x, conv, h, L, cfg, scan=scan_step):
    """Golden `mamba_block` op for op; returns (x', conv', h', p bits [..., E, N])."""
    R, N = cfg['dt_rank'], cfg['d_state']
    xn = rmsnorm(x)
    xi = gemv(L['W_in_x'], xn)
    u = conv_silu(xi, conv, L)
    dbc = gemv(L['W_x'], u)
    dt_low, B, C = dbc[..., :R], dbc[..., R:R + N], dbc[..., R + N:]
    dt = softplus(gemv(L['W_dt'], dt_low, init=L['b_dt']))
    z = gemv(L['W_in_z'], xn)
    h, y = scan(h, u, dt, B, C, L)
    g = mul(y, silu(z))
    p = mul(dt[..., None], L['A2'])
    return gemv(L['W_out'], g, init=x), xi, h, p



class ProbedHwModel(HwModel):
    """HwModel that records the last token's p (decay exponent) per layer in `self.p`."""

    def __init__(self, cfg, params, batch=1, decay='hw'):
        super().__init__(cfg, params, batch)
        self.scan = {'hw': scan_step, 'float': float_decay_scan}[decay]

    def _forward(self, x, P):
        self.p = []
        for l, L in enumerate(P['layers']):
            x, self.conv[l], self.h[l], p = probed_block(x, self.conv[l], self.h[l], L, self.cfg,
                                                         self.scan)
            self.p.append(p)
        return gemv(P['E_out'], rmsnorm(x))


def decay_of(p_bits):
    """dA bits for p bits (the scan's exp2 step)."""
    return exp2(p_bits)


def assert_matches_golden(cfg, P, tokens):
    """Probed and plain golden produce identical logits and state on a token sequence [b, T]."""
    a, b = HwModel(cfg, P, len(tokens)), ProbedHwModel(cfg, P, len(tokens))
    for t in range(tokens.shape[1]):
        assert np.array_equal(a.step(tokens[:, t]), b.step(tokens[:, t]))
    assert all(np.array_equal(x, y) for x, y in zip(a.h, b.h))
