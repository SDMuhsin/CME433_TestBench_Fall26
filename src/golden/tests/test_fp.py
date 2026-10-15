"""MAC-lane arithmetic: writeback rounding, FTZ, saturation, exact products, accumulation order."""
import numpy as np

from src.golden.arith.fp import FP16_MAX, canon16, dot, gemv, mul, to_fp16, value, writeback


def test_canon16_ftz_and_saturate():
    assert list(canon16([0x0001, 0x8000, 0x83FF, 0x7C00, 0xFC00, 0x7E00])) == \
        [0, 0, 0, FP16_MAX, 0x8000 | FP16_MAX, FP16_MAX]


def test_writeback_matches_numpy_rne_in_normal_range():
    rng = np.random.default_rng(0)
    x = (rng.standard_normal(100000) * 10.0 ** rng.uniform(-4, 4, 100000)).astype(np.float32)
    ok = (np.abs(x) >= 2 ** -14) & (np.abs(x) < 65504)
    assert np.array_equal(writeback(x[ok]), x[ok].astype(np.float16).view(np.uint16))


def test_writeback_ftz_saturate_no_negative_zero():
    out = writeback(np.array([2 ** -15, -2 ** -15, 0.0, -0.0, 1e9, -1e9], np.float32))
    assert list(out) == [0, 0, 0, 0, FP16_MAX, 0x8000 | FP16_MAX]


def test_writeback_scale_is_exact_before_rounding():
    acc = np.float32(1.0 + 2 ** -20)
    assert writeback(acc, -3) == to_fp16(0.125)
    assert writeback(np.float32(1.5), -20) == 0           # 1.5 * 2^-20 < 2^-14 -> FTZ


def test_products_are_exact(legal16):
    b, v = legal16
    rng = np.random.default_rng(1)
    i, j = rng.integers(0, len(b), (2, 200000))
    acc = dot([(b[i], b[j])])
    assert np.array_equal(acc.astype(np.float64), v[i] * v[j])


def test_dot_is_sequential_fp32_with_init():
    rng = np.random.default_rng(2)
    a, c = to_fp16(rng.standard_normal((2, 50)) * 100)
    init = to_fp16(3.0)
    ref = np.float32(3.0)
    for x, y in zip(value(a), value(c)):
        ref = np.float32(ref + x * y)
    assert dot([(a[k], c[k]) for k in range(50)], init=init) == ref


def test_exact_cancellation_gives_positive_zero():
    one, neg = to_fp16(1.0), to_fp16(-1.0)
    assert writeback(dot([(one, one), (neg, one)])) == 0
    assert mul(neg, np.uint16(0)) == 0


def test_gemv_matches_rowwise_dot():
    rng = np.random.default_rng(3)
    W = to_fp16(rng.standard_normal((5, 7)))
    x = to_fp16(rng.standard_normal((3, 7)))
    b = to_fp16(rng.standard_normal(5))
    y = gemv(W, x, init=b)
    for r in range(3):
        for o in range(5):
            assert y[r, o] == writeback(dot([(W[o, k], x[r, k]) for k in range(7)], init=b[o]))
