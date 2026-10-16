"""Reference model of the improved logarithmic multiplier (ILM-0, exact adders), Ansari,
Cockburn, Han, IEEE TC 70(4):614-625, 2021 (also Ansari, PhD thesis, U. Alberta 2019, Sec. 5.2).
Bit-exact to bench/variants/ilm.v.

Unsigned core, eq. (5.5)-(5.7): A = 2^k1 + q1 with 2^k1 the nearest power of two (nearest-one
detector, ties round up, no up-rounding beyond 2^(n-1)), A*B ~ 2^(k1+k2) + q1 2^k2 + q2 2^k1
(q1 q2 dropped). Signed INT8: sign-magnitude around the unsigned core (the paper's NN use).
"""
import numpy as np


def nod(x, n=8):
    """nearest power-of-two exponent k of x >= 1 (vectorised); x = 0 -> 0"""
    x = np.asarray(x, np.int64)
    k = np.zeros_like(x)
    for i in range(1, n):
        k = np.where(x >= (1 << i), i, k)                        # leading one
    up = (k >= 1) & (((x >> np.maximum(k - 1, 0)) & 1) == 1) & (k < n - 1)
    return np.where(up, k + 1, k)


def unsigned(a, b, n=8):
    """ILM product of unsigned n-bit a, b"""
    a, b = np.asarray(a, np.int64), np.asarray(b, np.int64)
    k1, k2 = nod(a, n), nod(b, n)
    p = (1 << (k1 + k2)) + (a - (1 << k1)) * (1 << k2) + (b - (1 << k2)) * (1 << k1)
    return np.where((a == 0) | (b == 0), 0, p)


def table():
    """256 x 256 signed product table T[a + 128, b + 128] (sign-magnitude ILM)."""
    r = np.arange(-128, 128)
    a, b = np.meshgrid(r, r, indexing='ij')
    return np.sign(a) * np.sign(b) * unsigned(np.abs(a), np.abs(b))


def paper_metrics(n=9):
    """unsigned 8-bit uniform metrics as in the thesis Table 5.4 (AE = mean(exact - approx),
    MRED, NMED = MED / 255^2); n = 9: NOD without the 2^(n-1) cap, as Table 5.4 implies"""
    r = np.arange(256)
    a, b = np.meshgrid(r, r, indexing='ij')
    e, ex = unsigned(a, b, n) - a * b, a * b
    nz = ex != 0
    return dict(AE=float(-e.mean()), MRED=float((np.abs(e[nz]) / ex[nz]).mean()),
                NMED=float(np.abs(e).mean() / 255 ** 2))


if __name__ == '__main__':
    for n, tag in ((9, 'uncapped NOD'), (8, 'NOD capped at 128')):
        print(f'unsigned ILM-0, {tag}:', {k: round(v, 4) for k, v in paper_metrics(n).items()},
              ' paper (Table 5.4, uniform): AE 0.25, MRED 0.0275, NMED 0.0068')
