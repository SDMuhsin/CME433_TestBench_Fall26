"""Bit-exact integer model of gan65_chip (64 -> 256 -> 256 -> 784 G300 generator) at datapath
width D = 8 (model/fmnist) or 16 (model/fmnist_w16, docs/width16.md).

Same arithmetic as rtl/seq/e2e_requant.v + the DLA PE array, S = the requant shift of the width
(quant.json "S"; 16 for INT8):
  acc = sum_k mul(W[r, k], x[k])            (2D + 8)-bit wrapping PE accumulator
  ReLU layers : q   = clamp((acc*MA + b*MB + 2^(S-1)) >> S, 0, 2^(D-1) - 1)
  tanh layer  : pre = (acc*MW4 + b*MB4 + 2^(S-1)) >> S (Q20), pixel = tanh_pixel(pre) (8-bit)
mul is the exact product unless a multiplier model is given: a 256 x 256 product table of an
8-bit variant (table[a + 128, b + 128] = gan_mul8(a, b)) or a vectorised function
f(a, b) -> products (a = weight, b = activation).
"""
import json

import numpy as np

from ..common.memh import read_memh
from ..common.paths import MODEL
from .tanh_rom import load_rom, tanh_pixel

CSR_NAMES = ('MA0', 'MB0', 'MA2', 'MB2', 'MW4', 'MB4')
SHAPES = {0: (256, 64), 2: (256, 256), 4: (784, 256)}


def load_model(mdir=MODEL):
    """-> dict W0, b0, W2, b2, W4, b4 (int64), the six CSR multipliers from csr.memh, the width
    D, the requant shift S and the accumulator width (quant.json; INT8 files predate 'width')."""
    q = json.loads((mdir / 'quant.json').read_text())
    w = int(q.get('width', 8))
    m = dict(width=w, S=int(q['S']), acc_w=2 * w + 8)
    for n, shape in SHAPES.items():
        m[f'W{n}'] = read_memh(mdir / f'G300_{n}_weight.memh', bits=w).reshape(shape)
        m[f'b{n}'] = read_memh(mdir / f'G300_{n}_bias.memh', bits=w)
    csr = read_memh(mdir / 'csr.memh', signed=False).reshape(6, 4)
    for name, b in zip(CSR_NAMES, csr):
        m[name] = int(b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24)
    m['rom'] = load_rom()
    return m


def wrap(v, bits):
    """Two's-complement wrap of int64 v to `bits`."""
    return ((v + (1 << (bits - 1))) & ((1 << bits) - 1)) - (1 << (bits - 1))


def matvec(W, x, acc_w, mul=None):
    """[N, in] activations x [out, in] weights -> [N, out] acc_w-bit accumulators."""
    if mul is None:
        return wrap(x @ W.T, acc_w)
    acc = np.zeros((x.shape[0], W.shape[0]), np.int64)
    for k in range(W.shape[1]):                       # per K column: mul(W[:, k], x[:, k])
        a, b = W[:, k][None, :], x[:, k][:, None]
        if callable(mul):
            acc += np.asarray(mul(*np.broadcast_arrays(a, b)), np.int64)
        else:
            acc += mul[a + 128, b + 128]
    return wrap(acc, acc_w)


def affine_shift(acc, b, ma, mb, s):
    """(acc*ma + b*mb + 2^(s-1)) >> s exactly (Python integers where int64 could overflow)."""
    big = (int(np.abs(acc).max(initial=0)) * ma + int(np.abs(b).max(initial=0)) * mb) >> 62
    if not big:
        return (acc * ma + b * mb + (1 << (s - 1))) >> s
    t = (acc.astype(object) * ma + b.astype(object) * mb + (1 << (s - 1))) >> s
    return t.astype(np.int64)


def relu_rq(acc, b, ma, mb, m):
    return np.clip(affine_shift(acc, b, ma, mb, m['S']), 0, (1 << (m['width'] - 1)) - 1)


def forward(zq, m, mul=None):
    """zq int[N, 64] -> dict h0 [N,256], h2 [N,256], pix [N,784] (int8 = uint8 pixel - 128)."""
    zq = np.asarray(zq, np.int64).reshape(-1, 64)
    aw = m['acc_w']
    h0 = relu_rq(matvec(m['W0'], zq, aw, mul), m['b0'], m['MA0'], m['MB0'], m)
    h2 = relu_rq(matvec(m['W2'], h0, aw, mul), m['b2'], m['MA2'], m['MB2'], m)
    pre = affine_shift(matvec(m['W4'], h2, aw, mul), m['b4'], m['MW4'], m['MB4'], m['S'])
    return dict(h0=h0, h2=h2, pix=tanh_pixel(pre, m['rom']))
