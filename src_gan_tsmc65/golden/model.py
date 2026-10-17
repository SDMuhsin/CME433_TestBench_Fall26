"""Bit-exact integer model of gan65_chip (64 -> 256 -> 256 -> 784 G300 generator).

Same arithmetic as rtl/seq/e2e_requant.v + the DLA PE array, S = 16:
  acc = sum_k mul(W[r, k], x[k])            24-bit wrapping PE accumulator
  ReLU layers : q   = clamp((acc*MA + b*MB + 2^15) >> 16, 0, 127)
  tanh layer  : pre = (acc*MW4 + b*MB4 + 2^15) >> 16 (Q20), pixel = tanh_pixel(pre)
mul is the exact product unless a 256 x 256 product table of a multiplier variant is given
(table[a + 128, b + 128] = gan_mul8(a, b), a = weight, b = activation).
"""
import numpy as np

from ..common.memh import read_memh
from ..common.paths import MODEL
from .tanh_rom import load_rom, tanh_pixel

S = 16
CSR_NAMES = ('MA0', 'MB0', 'MA2', 'MB2', 'MW4', 'MB4')
SHAPES = {0: (256, 64), 2: (256, 256), 4: (784, 256)}


def load_model(mdir=MODEL):
    """-> dict W0, b0, W2, b2, W4, b4 (int64) and the six CSR multipliers from csr.memh."""
    m = {}
    for n, shape in SHAPES.items():
        m[f'W{n}'] = read_memh(mdir / f'G300_{n}_weight.memh').reshape(shape)
        m[f'b{n}'] = read_memh(mdir / f'G300_{n}_bias.memh')
    csr = read_memh(mdir / 'csr.memh', signed=False).reshape(6, 4)
    for name, b in zip(CSR_NAMES, csr):
        m[name] = int(b[0] | b[1] << 8 | b[2] << 16 | b[3] << 24)
    m['rom'] = load_rom()
    return m


def wrap24(v):
    return ((v + (1 << 23)) & ((1 << 24) - 1)) - (1 << 23)


def matvec(W, x, table=None):
    """[N, in] activations x [out, in] weights -> [N, out] 24-bit accumulators."""
    if table is None:
        return wrap24(x @ W.T)
    acc = np.zeros((x.shape[0], W.shape[0]), np.int64)
    for k in range(W.shape[1]):                       # gather per K column: T[W[:, k], x[:, k]]
        acc += table[W[:, k][None, :] + 128, x[:, k][:, None] + 128]
    return wrap24(acc)


def relu_rq(acc, b, ma, mb):
    return np.clip((acc * ma + b * mb + (1 << (S - 1))) >> S, 0, 127)


def forward(zq, m, table=None):
    """zq int[N, 64] -> dict h0 [N,256], h2 [N,256], pix [N,784] (int8 = uint8 pixel - 128)."""
    zq = np.asarray(zq, np.int64).reshape(-1, 64)
    h0 = relu_rq(matvec(m['W0'], zq, table), m['b0'], m['MA0'], m['MB0'])
    h2 = relu_rq(matvec(m['W2'], h0, table), m['b2'], m['MA2'], m['MB2'])
    pre = (matvec(m['W4'], h2, table) * m['MW4'] + m['b4'] * m['MB4'] + (1 << (S - 1))) >> S
    return dict(h0=h0, h2=h2, pix=tanh_pixel(pre, m['rom']))
