"""Hardware layer operations built from MAC-lane ops and the shared LUT unit (spec section 5).

Every function is batched over leading dimensions; per-element op order is normative.
"""
import numpy as np

from ..arith.fp import dot, gemv, mul, writeback
from ..arith.nlu import exp2, rsqrt, silu, softplus

EPS_INIT = np.uint16(0x2400)   # 2^-6 accumulator init; after the 2^-6 mean scale eps = 2^-12
MEAN_SCALE = -6                # log2(1 / d_model)


def rmsnorm(x):
    """xn = FP16(x * rsqrt(FP16(2^-6 * (2^-6 + sum x_i^2)))); gain is folded into weights."""
    acc = dot([(x[..., i], x[..., i]) for i in range(x.shape[-1])], init=EPS_INIT)
    r = rsqrt(writeback(acc, MEAN_SCALE))
    return mul(x, r[..., None])


def conv_silu(xi, prev, L):
    """u = silu(FP16(b + w0 * prev + w1 * xi)), width-2 causal depthwise conv."""
    return silu(writeback(dot([(L['conv_w0'], prev), (L['conv_w1'], xi)], init=L['conv_b'])))


def scan_step(h, u, dt, B, C, L):
    """One selective-scan step for all channels; h [..., E, N] FP16 state -> (h', y [..., E])."""
    dtu = mul(dt, u)
    hn = np.empty_like(h)
    for n in range(h.shape[-1]):
        dA = exp2(mul(dt, L['A2'][:, n]))
        hn[..., n] = writeback(dot([(dA, h[..., n]), (dtu, B[..., n:n + 1])]))
    terms = [(C[..., n:n + 1], hn[..., n]) for n in range(h.shape[-1])] + [(L['D'], u)]
    return hn, writeback(dot(terms))


def mamba_block(x, conv, h, L, cfg):
    """Pre-norm Mamba block with residual; returns (x', conv', h')."""
    R, N = cfg['dt_rank'], cfg['d_state']
    xn = rmsnorm(x)
    xi = gemv(L['W_in_x'], xn)
    u = conv_silu(xi, conv, L)
    dbc = gemv(L['W_x'], u)
    dt_low, B, C = dbc[..., :R], dbc[..., R:R + N], dbc[..., R + N:]
    dt = softplus(gemv(L['W_dt'], dt_low, init=L['b_dt']))
    z = gemv(L['W_in_z'], xn)
    h, y = scan_step(h, u, dt, B, C, L)
    g = mul(y, silu(z))
    return gemv(L['W_out'], g, init=x), xi, h
