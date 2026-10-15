"""Spec section 4: lane MAC with product shift, writeback forms, saturation, RQ bounds."""
import numpy as np
import pytest

from src_int8.golden.ops.lane import dot, mac, rq, sh, wb_rq, wb_sh


def test_mac_exact_product_and_shift():
    a, b = np.array([(1 << 23) - 1, -(1 << 23), 3]), np.array([32767, -32768, -5])
    assert mac(10, a, b, 15).tolist() == [10 + ((((1 << 23) - 1) * 32767 + (1 << 14)) >> 15),
                                          10 + (((1 << 23) * 32768 + (1 << 14)) >> 15), 10 + 0]
    assert mac(0, a, np.array([255, -255, -5]), 0).tolist() == [((1 << 23) - 1) * 255, (1 << 23) * 255, -15]
    with pytest.raises(AssertionError):
        mac(0, a, b, 0)                                   # 2^38 product, no shift: not representable


def test_mac_rejects_operands_out_of_range():
    with pytest.raises(AssertionError):
        mac(0, 1 << 23, 1, 0)
    with pytest.raises(AssertionError):
        mac(0, 1, 32768, 0)


def test_mac_asserts_accumulator_bound():
    with pytest.raises(AssertionError):
        mac((1 << 31) - 1, 1, 1, 0)
    assert mac((1 << 31) - 2, 1, 1, 0) == (1 << 31) - 1


def test_dot_equals_sequential_macs_with_ps():
    rng = np.random.default_rng(0)
    for ps in (0, 6, 11):
        W = rng.integers(-(1 << 15), 1 << 15, (5, 40))
        x = rng.integers(-32768, 32768, (3, 40)) if ps else rng.integers(-256, 256, (3, 40))
        y = dot(W, x, ps, init=7)
        for r in range(3):
            for o in range(5):
                acc = 7
                for k in range(40):
                    acc = mac(acc, W[o, k], x[r, k], ps)
                assert y[r, o] == acc


def test_dot_bound_assertion():
    W = np.full((1, 96), 127)
    x = np.full((1, 96), 127)
    assert dot(W, x)[0, 0] == 96 * 127 * 127
    with pytest.raises(AssertionError):
        dot(np.full((1, 128), (1 << 23) - 1), np.full((1, 128), 32767))


def test_wb_sh_and_sh_saturation():
    acc = np.array([(1 << 30) + 123, -(1 << 30), 2047, 2048, -2048, -2049])
    assert wb_sh(acc, 12).tolist() == [(((1 << 30) + 123) + 2048) >> 12, -(1 << 18), 0, 1, 0, -1]
    assert sh(acc, 12, 8).tolist() == [127, -128, 0, 1, 0, -1]
    assert sh(acc, 0, 16, addend=np.array([0, 0, 1, 0, 0, 0])).tolist() == [32767, -32768, 2048, 2048, -2048, -2049]


def test_wb_rq_matches_definition_and_bounds():
    rng = np.random.default_rng(1)
    acc = rng.integers(-(1 << 31), 1 << 31, 10000)
    M = rng.integers(1 << 14, 1 << 15, 10000)
    s = rng.integers(1, 48, 10000)
    out = wb_rq(acc, np.stack([M, s], -1))
    ref = np.array([(int(a) * int(m) + (1 << (int(k) - 1))) >> int(k) for a, m, k in zip(acc, M, s)])
    assert np.array_equal(out, ref)
    for bad in ((1 << 14) - 1, 0), (1 << 15, 10), (1 << 14, 0), (1 << 14, 48):
        with pytest.raises(AssertionError):
            wb_rq(np.array([1]), np.array([bad]))


def test_rq_negative_ties_round_up():
    # acc * M = -3 * 2^(s-1): exactly half way -> rounds toward +inf
    pair = np.array([[1 << 14, 15]])
    acc = np.array([-3 * (1 << 14) // (1 << 14) * 1])   # -3 * 2^14 / M... use M = 2^14: acc * M = -3 * 2^14 = -1.5 * 2^15
    assert rq(acc, pair, 16)[0] == -1
    assert rq(np.array([3]), pair, 16)[0] == 2


def test_rq_saturates_each_width():
    pair = np.array([[1 << 14, 1]])           # multiply by 2^13
    acc = np.array([1 << 20, -(1 << 20), 1])
    assert rq(acc, pair, 8).tolist() == [127, -128, 127]
    assert rq(acc, pair, 16).tolist() == [32767, -32768, 8192]
    assert rq(acc, pair, 24).tolist() == [(1 << 23) - 1, -(1 << 23), 8192]
    assert rq(np.array([-5]), pair, 16, addend=np.array([-32768]))[0] == -32768   # -40960 - 32768
