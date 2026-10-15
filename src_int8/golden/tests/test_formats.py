"""Spec sections 2 and 3: rounding primitive, saturation, the format table."""
import numpy as np
import pytest

from src_int8.golden.ops.formats import ACT, PARAM, fits, rsh, sat


def test_rsh_round_half_up_including_negative_ties():
    v = np.array([5, 6, 7, -5, -6, -7, 0, 1, -1, 3, -3])
    assert rsh(v, 1).tolist() == [3, 3, 4, -2, -3, -3, 0, 1, 0, 2, -1]       # ties toward +inf
    assert rsh(v, 2).tolist() == [1, 2, 2, -1, -1, -2, 0, 0, 0, 1, -1]
    assert rsh(v, 0).tolist() == v.tolist()


def test_rsh_exhaustive_against_definition():
    v = np.arange(-70000, 70000, dtype=np.int64)
    for k in (1, 3, 11, 15, 19):
        assert np.array_equal(rsh(v, k), np.floor((v + 2.0 ** (k - 1)) / 2.0 ** k).astype(np.int64))


def test_rsh_large_products_are_exact():
    v = np.array([(1 << 39) - 1, -(1 << 39), (1 << 46) + 12345])
    assert rsh(v, 15).tolist() == [(((1 << 39) - 1) + (1 << 14)) >> 15, -(1 << 24), ((1 << 46) + 12345 + (1 << 14)) >> 15]


@pytest.mark.parametrize('w', [8, 16, 24])
def test_sat_edges(w):
    lim = 1 << (w - 1)
    v = np.array([lim - 1, lim, lim + 5, -lim, -lim - 1, 0, -(1 << 40), 1 << 40])
    assert sat(v, w).tolist() == [lim - 1, lim - 1, lim - 1, -lim, -lim, 0, -lim, lim - 1]


def test_sat_raw_32_passes_through():
    v = np.array([1 << 33, -(1 << 33)])
    assert np.array_equal(sat(v, 32), v)


def test_format_table_matches_spec_3_1():
    rows = {'X': (16, 8), 'XN': (8, 5), 'XI': (8, 4), 'XC': (16, 8), 'U': (8, 4), 'DL': (8, 3),
            'B': (8, 5), 'C': (8, 4), 'DT_PRE': (16, 8), 'DT': (16, 12), 'BU': (16, 9), 'P': (32, 19),
            'DA': (16, 15), 'H': (24, 17), 'Y': (16, 9), 'Z': (16, 8), 'SIG': (16, 15), 'SZ': (16, 8),
            'G': (8, 4), 'MS': (32, 16), 'R': (16, 9), 'LOGITS': (16, 8)}
    assert {k: (f.width, f.frac) for k, f in ACT.items()} == rows
    assert not ACT['DA'].signed and not ACT['SIG'].signed and not ACT['MS'].signed
    assert ACT['H'].hi * ACT['H'].scale < 64 <= (ACT['H'].hi + 1) * ACT['H'].scale
    assert {k: (f.width, f.frac) for k, f in PARAM.items()} == \
        {'D': (8, 6), 'A2': (16, 7), 'CB': (16, 8), 'B_DT': (16, 8), 'E_IN': (16, 8)}


def test_fits():
    assert fits([127, -128], 8) and not fits([128], 8) and fits([65535], 16, signed=False)
