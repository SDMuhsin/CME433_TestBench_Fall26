"""Quantisation-aware forward of a `MambaLM`: every tensor of spec table 3.1 is fake-quantised
at the point where the chip stores it, every parameter as the exporter will quantise it.

The float parameters stay those of `MambaLM` (so a QAT checkpoint has the same format as the
float checkpoint); the norm gains are folded into the following weights before the per-row
quantisation, exactly as `golden/io/weights.py` does at export time.
"""
import math

import torch
import torch.nn.functional as F

from ...golden.ops.formats import A2_HI, A2_LO, ACT, EPS_INIT, PARAM
from ..config import EPS
from ..float.scan import scan_with_decay
from .ste import fq, fq_rows

LOG2E = math.log2(math.e)
LUT_IN_MAX = 8.0                                     # sigmoid / softplus LUT input range
DT_MAX = ACT['DT'].hi * ACT['DT'].scale              # 8 - 2^-12
H_CLIP = float(1 << (ACT['H'].width - 1 - ACT['H'].frac))   # 64
assert EPS_INIT * ACT['MS'].scale == EPS


def q_sigmoid(x):
    """sigmoid on the LUT's input range, rounded to SIG Q0.15."""
    return fq(torch.sigmoid(x.clamp(-LUT_IN_MAX, LUT_IN_MAX)), ACT['SIG'])


def q_softplus(x):
    """softplus on the LUT's input range, saturating at 8 - 2^-12, rounded to DT Q3.12."""
    return fq(F.softplus(x.clamp(-LUT_IN_MAX, LUT_IN_MAX)).clamp(max=DT_MAX), ACT['DT'])


def q_rmsnorm(x):
    """xn = fq8(x * fq(rsqrt(mean x^2 + eps))); the gain is folded into the next weights."""
    r = fq(torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + EPS), ACT['R'])
    return fq(x * r, ACT['XN'])


def q_block(blk, x):
    """One Mamba block, fake-quantised; x [b, T, d_model] in X format -> x' in X format."""
    cfg = blk.cfg
    R, N, E = cfg.dt_rank, cfg.d_state, cfg.d_inner
    xn = q_rmsnorm(x)
    W_in = fq_rows(blk.in_proj.weight * blk.norm.weight[None, :])
    xi = fq(xn @ W_in[:E].t(), ACT['XI'])
    z = fq(xn @ W_in[E:].t(), ACT['Z'])

    cw = fq_rows(blk.conv_w)                                     # one scale per channel
    cb = fq(blk.conv_b, PARAM['CB'])
    prev = F.pad(xi, (0, 0, 1, 0))[:, :-1]
    xc = fq(cb + cw[:, 0] * prev + cw[:, 1] * xi, ACT['XC'])
    u = fq(xc * q_sigmoid(xc), ACT['U'])

    dbc = u @ fq_rows(blk.x_proj.weight).t()
    dl = fq(dbc[..., :R], ACT['DL'])
    B = fq(dbc[..., R:R + N], ACT['B'])
    C = fq(dbc[..., R + N:], ACT['C'])

    dt_pre = fq(dl @ fq_rows(blk.dt_proj.weight).t() + fq(blk.dt_proj.bias, PARAM['B_DT']),
                ACT['DT_PRE'])
    dt = q_softplus(dt_pre)
    A2 = fq((-torch.exp(blk.A_log) * LOG2E).clamp(A2_LO, A2_HI), PARAM['A2'])
    p = dt[..., None] * A2                                       # exact product in hardware
    dA = torch.where(p <= -16.0, torch.zeros_like(p), fq(torch.exp2(p), ACT['DA']))
    y = scan_with_decay(u, dt, dA, B, C, h_clip=H_CLIP)
    y = fq(y + fq(blk.D, PARAM['D']) * u, ACT['Y'])

    sz = fq(z * q_sigmoid(z), ACT['SZ'])
    g = fq(y * sz, ACT['G'])
    return fq(x + g @ fq_rows(blk.out_proj.weight).t(), ACT['X'])


def q_forward(model, tokens):
    """tokens [b, T] -> logits [b, T, vocab] in LOGITS format (Q7.8 values)."""
    x = fq(model.embed(tokens), PARAM['E_IN'])
    for blk in model.blocks:
        x = q_block(blk, x)
    E_out = fq_rows(model.embed.weight * model.norm_f.weight[None, :])
    return fq(q_rmsnorm(x) @ E_out.t(), ACT['LOGITS'])
