"""Amirafshar, Baroughi, Shahhoseini, TaheriNejad, "Carry Disregard Approximate Multipliers",
IEEE TCAS-I 70(12):4840-4853, 2023 (CDM).

An 8 x 8 multiplier is split into two 8 x 4 array multipliers (eq. 1, Fig. 2): group A = A x B_L
(b0..b3), group B = A x B_H (b4..b7), added by one exact adder. In 8 x 4 multiplier cd_x the
carries of (1-based) columns 2 .. x are disregarded (Fig. 3-4): those columns become the XOR
of their partial products (cells PPU1 = AND + XOR), the carry into column x + 1 is lost and
columns > x are exact. Column k holds a_i b_j with i + j = k - 1; dropping its carries costs
2^k floor(L_k / 2), L_k = number of ones in the column (eqs. 3-5). CDM8_xy = cd_x in group A
and cd_y in group B (Table I; x, y hexadecimal, cd_1 = exact): ED = ED_cdx + 2^4 ED_cdy (eq. 8).
CDM16 (Fig. 5, Table II) = four CDM8s and four 8-bit adders (CLAx) that drop their final carry.

`ed8x4`/`unsigned8`/`unsigned16` are the analytic reference (eqs. 2-24, Python ints / numpy);
`matrix` / `cdm` build the bit-level netlist: the paper's XOR columns, the remaining partial
products reduced exactly (Dadda tree + one adder).

The paper is unsigned only. Signed extension `mode='sm'` (gan_mul8 variants): sign-magnitude
with no carry chain. Magnitudes in one's complement, a' = a xor a7, b' = b xor b7 (7 bit,
|a| = a' + a7); the CDM works on a' x b' and the correction rows a7 b' + b7 a' + a7 b7 are
added exactly, so V = CDM(a', b') + ... = |a||b| - ED(a', b'). The product sign s = a7 xor b7
is applied inside the bit matrix: -V = sum (bit xor s) 2^k - s C (C = sum of the weights of
all matrix bits), i.e. every bit is XOR-ed with s and s is added at the set bits of -C mod
2^16. Errors are the paper's ED with the sign of the product (unbiased), and a zero operand
gives 0. `mode='bw'` (ablation): Baugh-Wooley two's complement, carries disregarded among
the plain AND bits a_i b_j only (sign-row / sign-column bits and constant exact); for a
negative operand the dense two's-complement bits lose many carries, all errors are <= 0.
"""
import numpy as np

from .cells import EXACT
from .matrix import BitMatrix
from .mult import build
from .netlist import Net, ZERO

N = 8
# Table II: CDM16 digit -> CDM8_xy used for that sub-multiplier (0 = exact)
CDM16_DIGIT = {'0': (1, 1), '3': (4, 1), '7': (8, 4), '8': (9, 5), 'b': (10, 8), 'f': (10, 10)}


def ed8x4(a, b4, x):
    """Error distance of the 8 x 4 multiplier cd_x for a in [0, 256), b4 in [0, 16)."""
    a, b4 = np.asarray(a, np.int64), np.asarray(b4, np.int64)
    ed = np.zeros(np.broadcast(a, b4).shape, np.int64)
    for k in range(2, x + 1):
        ones = sum(((a >> (k - 1 - j)) & 1) * ((b4 >> j) & 1)
                   for j in range(4) if 0 <= k - 1 - j < N)
        ed += (ones // 2) << k
    return ed


def unsigned8(a, b, x, y):
    """CDM8_xy (eq. 8): exact product minus the disregarded carries of both groups."""
    a, b = np.asarray(a, np.int64), np.asarray(b, np.int64)
    return a * b - ed8x4(a, b & 15, x) - (ed8x4(a, b >> 4, y) << 4)


def unsigned16(a, b, digits):
    """CDM16_wxyz (Fig. 5, eqs. 9-21): MUL_1..MUL_4 = CDM8s of the Table II digits on
    A_L B_L, A_H B_L, A_L B_H, A_H B_H; CLAx1-2 add MUL_1 high + MUL_2 low + MUL_3 low, CLAx3-4
    add MUL_2 high + MUL_3 high + MUL_4 low, each dropping its carry out of 8 bits."""
    a, b = np.asarray(a, np.int64), np.asarray(b, np.int64)
    al, ah, bl, bh = a & 255, a >> 8, b & 255, b >> 8
    r = [unsigned8(p, q, *CDM16_DIGIT[d]) for d, (p, q) in
         zip(digits, ((al, bl), (ah, bl), (al, bh), (ah, bh)))]
    lo, hi = (lambda v: v & 255), (lambda v: v >> 8)
    s1 = (hi(r[0]) + lo(r[1]) + lo(r[2])) & 255
    s2 = (hi(r[1]) + hi(r[2]) + lo(r[3])) & 255
    return lo(r[0]) + (s1 << 8) + (s2 << 16) + (hi(r[3]) << 24)


def signed8(a, b, x, y):
    """Signed CDM8_xy, mode 'sm' (module doc), analytic; equals the netlist on all inputs."""
    a, b = np.asarray(a, np.int64), np.asarray(b, np.int64)
    sa, sb = (a < 0).astype(np.int64), (b < 0).astype(np.int64)
    am, bm = np.where(sa, ~a, a), np.where(sb, ~b, b)
    v = unsigned8(am, bm, x, y) + sa * bm + sb * am + sa * sb
    return np.where(sa ^ sb, -v, v)


def signed16(a, b, digits):
    """Signed CDM16_wxyz, the sign-magnitude scheme of signed8 around unsigned16: 15-bit
    one's-complement magnitudes, exact correction terms, exact sign application."""
    a, b = np.asarray(a, np.int64), np.asarray(b, np.int64)
    sa, sb = (a < 0).astype(np.int64), (b < 0).astype(np.int64)
    am, bm = np.where(sa, ~a, a), np.where(sb, ~b, b)
    v = unsigned16(am, bm, digits) + sa * bm + sb * am + sa * sb
    return np.where(sa ^ sb, -v, v)


class Cdm16:
    """CDM16_wxyz with the `products()` interface of mult.Multiplier (for exhaustive.py);
    signed=True: the sign-magnitude extension (signed16)."""

    def __init__(self, digits, signed=False):
        self.digits, self.n, self.signed = digits, 16, signed

    def products(self, a, b):
        return (signed16 if self.signed else unsigned16)(a, b, self.digits)


def matrix(net, a, b, x, y, bw=False):
    """Bit matrix of CDM8_xy: per group and disregarded column one XOR of its plain partial
    products; every other bit (with bw: the Baugh-Wooley sign terms) as in the exact array."""
    n = len(a)
    mat = BitMatrix(net, 2 * n)
    xor = {}                                         # (group, column) -> XOR of plain bits
    for j in range(n):
        g, j0 = (0, 0) if j < 4 else (1, 4)
        last = (x, y)[g]
        for i in range(n):
            col = i + j
            bit = net.AND(a[i], b[j])
            if bit == ZERO:
                continue
            bit = net.name(bit, f'pp_{i}_{j}')
            neg = bw and (i == n - 1) != (j == n - 1)
            if not neg and 2 <= col - j0 + 1 <= last and not (bw and i == j == n - 1):
                xor[(g, col)] = net.XOR(xor.get((g, col), ZERO), bit)
            else:
                mat.add(col, bit, negative=neg)
    for (g, col), bit in sorted(xor.items()):
        mat.add(col, net.name(bit, f'cd{"ab"[g]}_{col}'))
    return mat


def negate_if(net, cols, s):
    """Columns of (s ? -V : V) for the columns of V: each bit XOR s, plus s at the set bits
    of -C mod 2^w, C = sum of the weights of the bits (constant-1 bits included)."""
    w = len(cols)
    out = [[net.XOR(bit, s) for bit in col if bit != ZERO] for col in cols]
    c = sum(sum(bit != ZERO for bit in col) << k for k, col in enumerate(cols))
    k = -c % (1 << w)
    for i in range(w):
        if (k >> i) & 1:
            out[i].append(s)
    return out


def sign_magnitude(net, a, b, x, y):
    """Columns of the signed CDM8_xy, mode 'sm' (module doc)."""
    n = len(a)
    sa, sb = a[n - 1], b[n - 1]
    am = [net.name(net.XOR(v, sa), f'am_{i}') for i, v in enumerate(a[:-1])] + [ZERO]
    bm = [net.name(net.XOR(v, sb), f'bm_{i}') for i, v in enumerate(b[:-1])] + [ZERO]
    mat = matrix(net, am, bm, x, y)
    for i in range(n - 1):
        mat.add(i, net.name(net.AND(sa, bm[i]), f'ca_{i}'))
        mat.add(i, net.name(net.AND(sb, am[i]), f'cb_{i}'))
    mat.add(0, net.AND(sa, sb))
    return negate_if(net, mat.columns(), net.name(net.XOR(sa, sb), 'sgn'))


def cdm(x, y, mode='sm', n=N):
    """8 x 8 CDM8_xy, netlist + model. mode: 'sm' signed (sign-magnitude), 'bw' signed
    (Baugh-Wooley ablation), 'unsigned' (the paper's design)."""
    net = Net()
    a, b = net.bus('a', n), net.bus('b', n)
    if mode == 'sm':
        cols = sign_magnitude(net, a, b, x, y)
    else:
        cols = matrix(net, a, b, x, y, bw=mode == 'bw').columns()
    return build(net, a, b, cols, lambda i: EXACT, signed=mode != 'unsigned')


def name(x, y):
    return f'CDM8_{x:x}{y:x}'
