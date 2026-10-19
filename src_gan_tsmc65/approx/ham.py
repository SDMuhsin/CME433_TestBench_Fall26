"""Hybrid approximate multipliers (HAM) of Shi, Cao, Zou, Gao, Wu, "Hybrid Approximate
Multipliers With Merits Balance for Digital Processing and Neural Networks", IEEE TVLSI
33(10):2795-2805, 2025, as a bit-exact integer model.

Signed w x w (Fig. 3): magnitude extraction (ME), leading-one detection, exponent e = k + 1
(k = leading-one position) and an F-bit mantissa f (fraction bits after the leading one),
mixed piecewise-linear fit of p1 = (1 + f1)(1 + f2) (eq. 6), magnitude-to-signed (MTS),
shift by K = e1 + e2. All quantities below are integers in units of 2^-F.

  X1 = f1 + f2 (HnLm: the n-2 upper mantissa bits added exactly, the m lower ones OR-ed)
  X2 = f1[top x2b] - f2[top x2b]   X3 = f1[top x3b] + f2[top x3b]   (eq. 4)
  X4 = sign(X2) ? f1 : f2, kept to its x4b upper bits (min(f1, f2), eq. 6)
  Zone 1: X3 < z1                            p1 ~ X1 + X4 / 4      + Bias1
  Zone 2: |X2| <= z2      (z1 <= X3 < z5)    p1 ~ X1 + X1 / 2      + Bias2
  Zone 3: z2 < |X2| < z4  (z1 <= X3 < z5)    p1 ~ X1 + X1 / 2      + Bias3
  Zone 4: |X2| >= z4      (z1 <= X3 < z5)    p1 ~ X1 + X4          + Bias4
  Zone 5: X3 >= z5                           p1 ~ 2 X1 - X1 / 16   + Bias5
Paper zones (Fig. 1(c), 16 bit): z1 = 4 (X3 < 1/2), z5 = 10 (X3 >= 5/4) in 1/8, z2 = 3, z4 = 9
in 1/16. Shifted terms are floored at F fraction bits.

Types (Section II-B):
  HnLm  F = n + m - 2; the upper n bits of p1_PWL from an exact 3-operand adder without
        carry-out (mod 2^n), the lower m bits the OR of the three terms (LOA), no carry
        between them.
  HnC1  F = n - 1; the exact sum is truncated to its n upper bits (n - 2 fraction bits),
        the carry from the dropped column kept (C1); HnC0: F = n - 2, nothing dropped.
p1_PWL = P1 with q fraction bits (q = n - 2 for HnC, F for HnLm). Biases are given in units
of 2^-bf (Table I: bf = 8) and aligned to F.

ME: 'pacc' |x| ~ {~x[w-2:4], (~x[3:0] + 1) mod 16} (partial complement, the carry out of the
4 LSBs dropped), 'oc' |x| ~ ~x (one's complement): w - 1 magnitude bits as in the paper
(|-2^(w-1)| is not representable; PACC gives 2^(w-1) - 16); 'exact': |x| on w bits.
MTS: 'sc' sign compensation (biases pre-reduced by one LSB, the vacant carry bit = ~sign):
the signed result is exactly -P1 for a negative product; 'oc': ~P1 = -P1 - 1.
SHIFT: the q-fraction-bit P1 is scaled by 2^(K - 2 - q); right shifts are arithmetic and
truncate, `bct` adds bring-in carry truncation (Fig. 5(a)): the last two kept bits A, B
become A | B C and (B ^ C) | A C with C the first dropped bit (saturating round).
Output (16 bit, Fig. 5(b)): 'full', 'so' (K >= w [K[4] = 1]: low w - 1 product bits
zero, otherwise 0), 'sp' (K >= w: low w - 1 bits zero, otherwise unchanged).
A zero magnitude (A == 0, B == 0, or a PACC magnitude of 0) gives a product of 0.
"""
from dataclasses import dataclass, replace

import numpy as np


@dataclass(frozen=True)
class Ham:
    w: int                      # operand width (signed)
    n: int                      # exact (upper) p1_PWL bits
    m: int = 0                  # LOA bits (HnLm); 0 for HnC
    c: int = 1                  # HnC: carry from the dropped column (1) or no dropped column (0)
    biases: tuple = (259, 197, 190, 254, 36)
    bf: int = 8                 # bias fraction bits
    x2b: int = 4
    x3b: int = 3
    x4b: int = 0                # 0 = full mantissa
    zones: tuple = (4, 10, 3, 9)    # z1, z5 (X3 units), z2, z4 (|X2| units)
    me: str = 'pacc'
    mts: str = 'sc'
    bct: bool = False
    out: str = 'full'
    signed: bool = True
    loa: str = 'both'           # HnLm: OR-ed low part in X1 and p1 ('both'), 'x1' or 'p1' only

    @property
    def F(self):
        return self.n + self.m - 2 if self.m else self.n - 2 + self.c

    @property
    def q(self):
        return self.F if self.m else self.n - 2

    def with_(self, **kw):
        return replace(self, **kw)

    def products(self, a, b):
        a = np.asarray(a, np.int64).ravel()
        b = np.asarray(b, np.int64).ravel()
        return signed(self, a, b)


def magnitude(x, w, me):
    """(|x| approximation on w - 1 bits, sign)."""
    neg = x < 0
    lo = (1 << (w - 1)) - 1
    if me == 'exact':
        mag = np.abs(x)
    elif me == 'oc':
        mag = np.where(neg, ~x & lo, x)
    else:
        inv = ~x & lo
        mag = np.where(neg, (inv & ~15 & lo) | ((inv + 1) & 15), x)
    return mag, neg


def lod(v, width):
    """Leading-one position of v (0 for v = 0)."""
    k = np.zeros(v.shape, np.int64)
    for i in range(1, width):
        k = np.where(v >> i != 0, i, k)
    return k


def mantissa(mag, k, mw, F):
    """F-bit fraction after the leading one (mag has mw significant bits at most)."""
    fr = (mag << (mw - 1 - k)) & ((1 << (mw - 1)) - 1)       # mw - 1 fraction bits
    return fr >> (mw - 1 - F) if F <= mw - 1 else fr << (F - mw + 1)


def p1_pwl(h, f1, f2):
    """Mixed PWL approximation of (1 + f1)(1 + f2) * 2^F; returns P1 with q fraction bits."""
    F, m = h.F, h.m
    if m and h.loa != 'p1':
        lo = (1 << m) - 1
        x1 = (((f1 >> m) + (f2 >> m)) << m) | ((f1 | f2) & lo)
    else:
        x1 = f1 + f2
    d = (f1 >> (F - h.x2b)) - (f2 >> (F - h.x2b))
    ad = np.abs(d)
    x3 = (f1 >> (F - h.x3b)) + (f2 >> (F - h.x3b))
    x4 = np.where(d < 0, f1, f2)
    if h.x4b:
        x4 = (x4 >> (F - h.x4b)) << (F - h.x4b)
    z1, z5, z2, z4 = h.zones
    zone = np.where(x3 < z1, 1, np.where(x3 >= z5, 5, np.where(ad <= z2, 2, np.where(ad >= z4, 4, 3))))
    bias = np.asarray(h.biases, np.int64)[zone - 1]
    bias = bias << (F - h.bf) if F >= h.bf else bias >> (h.bf - F)
    t1 = np.where(zone == 5, x1 << 1, x1)
    t2 = np.select([zone == 1, zone == 4, zone == 5], [x4 >> 2, x4, -(x1 >> 4)], x1 >> 1)
    if m and h.loa != 'x1':
        W = h.n + m
        mask = (1 << W) - 1
        t2 = t2 & mask                                       # two's complement on W bits
        hi = ((t1 >> m) + (t2 >> m) + (bias >> m)) & ((1 << h.n) - 1)
        return (hi << m) | ((t1 | t2 | bias) & ((1 << m) - 1))
    return (t1 + t2 + bias) >> (F - h.q)


def bct(v, s):
    """Right shift v by s >= 0 with bring-in carry truncation of the last two kept bits."""
    kept = v >> s
    c = np.where(s > 0, (v >> np.maximum(s - 1, 0)) & 1, 0)
    a1, b0 = (kept >> 1) & 1, kept & 1
    na, nb = a1 | (b0 & c), (b0 ^ c) | (a1 & c)
    return (kept & ~3) | (na << 1) | nb


def signed(h, a, b):
    w = h.w
    mw = w - 1 if h.signed and h.me != 'exact' else w           # magnitude bits
    if h.signed:
        ma, sa = magnitude(a, w, h.me)
        mb, sb = magnitude(b, w, h.me)
    else:
        ma, mb, sa, sb = a, b, a < 0, b < 0
    ka, kb = lod(ma, mw), lod(mb, mw)
    p1 = p1_pwl(h, mantissa(ma, ka, mw, h.F), mantissa(mb, kb, mw, h.F))
    neg = sa ^ sb
    of = np.where(neg, -p1 if h.mts == 'sc' else ~p1, p1)
    sh = ka + kb - h.q                                         # = K - 2 - q
    left = of << np.maximum(sh, 0)
    if h.bct:
        right = bct(of, np.maximum(-sh, 0))
    else:
        right = of >> np.maximum(-sh, 0)
    v = np.where(sh >= 0, left, right)
    if h.out != 'full':
        big = ka + kb + 2 >= w                                 # K[4] = 1 at w = 16
        hi = (v >> (w - 1)) << (w - 1)
        v = np.where(big, hi, 0 if h.out == 'so' else v)
    return np.where((ma == 0) | (mb == 0), 0, v)


def build(h):
    """Module-level builder for exhaustive.py worker pools."""
    return h


# Paper configurations. 16 bit (Tables I-II): H9C1 (PACC, SC, BCT) and H6L9 (PACC, OC); the -SP /
# -SO versions use OC magnitudes, no BCT and the segment outputs of Fig. 5(b).
H9C1 = Ham(16, 9, 0, c=1, biases=(259, 197, 190, 254, 36), mts='sc', bct=True)
H6L9 = Ham(16, 6, 9, biases=(259, 200, 192, 256, 35), mts='oc')
PAPER16 = {'H6L9': H6L9, 'H6L9-SP': H6L9.with_(me='oc', out='sp'),
           'H6L9-SO': H6L9.with_(me='oc', out='so'), 'H9C1': H9C1,
           'H9C1-SP': H9C1.with_(me='oc', bct=False, out='sp'),
           'H9C1-SO': H9C1.with_(me='oc', bct=False, out='so')}
# 8 bit H7C0 HAM-A/B/C (Table V): X2 keeps 3/2/2, X4 5/4/3 mantissa MSBs. Fig. 1(c) zones on the
# coarser X2 grid (|X2| <= 3/16 -> 1/8 or 0, >= 9/16 -> 5/8 or 3/4); the paper does not print the
# 8-bit biases: these (units 2^-5) minimise the unsigned exhaustive MRED (paper_shi2025.fit).
HAM8 = {'A': Ham(8, 7, 0, c=0, bf=5, x2b=3, x4b=5, zones=(4, 10, 1, 5), biases=(33, 25, 24, 32, 5)),
        'B': Ham(8, 7, 0, c=0, bf=5, x2b=2, x4b=4, zones=(4, 10, 0, 3), biases=(33, 25, 24, 33, 5)),
        'C': Ham(8, 7, 0, c=0, bf=5, x2b=2, x4b=3, zones=(4, 10, 0, 3), biases=(33, 25, 24, 34, 5))}
