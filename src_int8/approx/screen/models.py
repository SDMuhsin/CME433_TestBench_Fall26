"""Screening models (256 x 256 product tables T[a + 128, b + 128]) of the shortlisted designs.

These are behavioural models used only to screen the language-model impact with the emulator
before any RTL is written (src_int8/docs/approx_cssm.md, shortlist). Only cssm has a full RTL
reproduction (bench/variants/cssm.v, bit-exact to ref/cssm.py); `du24` and `cn_yang1` are
simplified models of the published structures (see the notes on each).
"""
import numpy as np

from ..ref import cssm

R = np.arange(-128, 128)
A, B = np.meshgrid(R, R, indexing='ij')


def _wrap16(x):
    return ((x + 32768) & 0xffff) - 32768


def _sign_magnitude(f):
    """signed product from an unsigned model f(|a|, |b|) (sign-magnitude extension)"""
    return np.sign(A) * np.sign(B) * f(np.abs(A), np.abs(B))


def _lead(x):
    """position of the leading one (0 for x <= 1)"""
    k = np.zeros_like(x)
    for i in range(1, 9):
        k = np.where(x >= (1 << i), i, k)
    return k


def mitchell():
    """Mitchell's logarithmic multiplier (1962), full precision, sign-magnitude: reference point."""
    def f(a, b):
        ka, kb = _lead(a), _lead(b)
        s = a * (1 << kb) + b * (1 << ka) - 2 * (1 << (ka + kb))   # 2^(ka+kb) (xa + xb)
        p = np.where(s < (1 << (ka + kb)), (1 << (ka + kb)) + s, 2 * s)
        return np.where((a == 0) | (b == 0), 0, p)
    return _sign_magnitude(f)


def ilm():
    """Improved logarithmic multiplier (Ansari, Cockburn, Han, IEEE TC 2021): nearest-one
    detector, A*B ~ 2^(ka+kb) + qa 2^kb + qb 2^ka (qa qb dropped), full width, sign-magnitude."""
    def f(a, b):
        def near(x):
            k = _lead(x)
            up = (k >= 1) & (((x >> np.maximum(k - 1, 0)) & 1) == 1)
            return np.where(up, k + 1, k)
        na, nb = near(a), near(b)
        p = (1 << (na + nb)) + (a - (1 << na)) * (1 << nb) + (b - (1 << nb)) * (1 << na)
        return np.where((a == 0) | (b == 0), 0, p)
    return _sign_magnitude(f)


def _bw_ppm():
    """Baugh-Wooley partial products: list of (column, bit array), constants included."""
    a, b = A & 0xff, B & 0xff
    pps = []
    for i in range(8):
        for j in range(8):
            pp = ((a >> i) & 1) & ((b >> j) & 1)
            pps.append((i + j, (1 - pp) if (i == 7) ^ (j == 7) else pp))
    one = np.ones_like(A)
    return pps + [(8, one), (15, one)]


def du24(trunc_num=7, comp=192):
    """Du et al., IEEE OJCAS 2024: Baugh-Wooley PPM with the trunc_num least significant
    columns truncated and the constant C_c added (Table 1: t = 3 -> C_c = 192). The paper's
    probability-optimised compressor (mean error -0.08) is not modelled."""
    tot = sum(pp << c for c, pp in _bw_ppm() if c >= trunc_num)
    return _wrap16(tot + comp)


def cn_yang1(ncols=8):
    """Strollo et al., IEEE TCAS-I 2020, signed 8 x 8 C-N configuration: approximate 4-2
    compressors (Yang1, saturating: four ones -> 3) in the 8 least significant columns of the
    Baugh-Wooley PPM, exact elsewhere. The compressor grouping is simplified (not the paper's
    Dadda wiring), so the error is of the published order, not equal to it."""
    cols = [[] for _ in range(17)]
    for c, pp in _bw_ppm():
        cols[c].append(pp)
    for _ in range(4):
        new = [[] for _ in range(17)]
        for c in range(16):
            bits, k = cols[c], 0
            if c < ncols and len(bits) > 2:
                while len(bits) - k >= 4:
                    s = np.minimum(bits[k] + bits[k + 1] + bits[k + 2] + bits[k + 3], 3)
                    new[c].append(s & 1)
                    new[c + 1].append(s >> 1)
                    k += 4
            new[c].extend(bits[k:])
        cols = new
    return _wrap16(sum(sum(cols[c]) << c for c in range(16) if cols[c]))


def probe_bias(c):
    """sensitivity probe: exact product + constant c"""
    return A * B + c


def probe_sm_trunc(k):
    """sensitivity probe: sign-magnitude product with its k LSBs cleared (error toward zero)"""
    return _sign_magnitude(lambda a, b: (a * b) >> k << k)


MODELS = {
    'probe_bias2': lambda: probe_bias(2),
    'probe_smtrunc4': lambda: probe_sm_trunc(4),
    'mitchell': mitchell,
    'ilm': ilm,
    'du24_t7': lambda: du24(7, 192),
    'du24_t4': lambda: du24(4, 12),
    'cn_yang1': cn_yang1,
    'cssm4': lambda: cssm.table(4, 1),
    'cssm5': lambda: cssm.table(5, 1),
    'cssm6': lambda: cssm.table(6, 1),
    'cssm7': lambda: cssm.table(7, 1),
}
