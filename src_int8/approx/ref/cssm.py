"""Reference model of the signed static segmented multiplier with correction (C-SSM),
Strollo et al., TCAS-I 69(6), 2022, eq. (15)-(17), (20). Bit-exact to bench/variants/cssm.v."""
import numpy as np


def operand(x, m, corr, n=8):
    """-> (m-bit signed value, shift) of one operand (vectorised over int arrays)."""
    s = n - m
    fits = (x >= -(1 << (m - 1))) & (x < (1 << (m - 1)))      # alpha_X all-0 or all-1
    h = x >> s                                                # H_X = X[n-1:n-m] (arithmetic)
    if corr:                                                  # eq. (20): LSB := x[s] | x[s-1]
        h = (h & ~1) | ((h & 1) | ((x >> (s - 1)) & 1))
    return np.where(fits, x, h), np.where(fits, 0, s)


def table(CSSM_M=6, CSSM_CORR=1):
    """256 x 256 product table T[a + 128, b + 128]."""
    r = np.arange(-128, 128)
    a, b = np.meshgrid(r, r, indexing='ij')
    va, sa = operand(a, int(CSSM_M), int(CSSM_CORR))
    vb, sb = operand(b, int(CSSM_M), int(CSSM_CORR))
    return (va * vb) << (sa + sb)
