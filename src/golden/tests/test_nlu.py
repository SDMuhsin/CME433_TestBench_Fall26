"""Shared LUT unit: ROM image, address generation edge cases, exhaustive accuracy."""
import numpy as np

from src.golden.arith.fp import canon16, to_fp16, value
from src.golden.arith.nlu import (EXP2, FRAC_BITS, FUNCS, ROM, ROM_WORDS, RSQRT, SIGMOID, address, exp2,
                            rsqrt, sigmoid, silu, softplus)


def f16(x):
    return to_fp16(np.asarray(x, dtype=np.float64))


def test_rom_layout_and_contents():
    assert ROM_WORDS == 340 and len(ROM) == 340
    assert np.array_equal(canon16(ROM), ROM)
    ends = [(fn.base, fn.base + fn.segments + 1) for fn in FUNCS]
    assert all(a[1] == b[0] for a, b in zip(ends, ends[1:])) and ends[-1][1] == ROM_WORDS
    assert value(ROM[EXP2.base]) == 1 and value(ROM[EXP2.base + 32]) == 2
    assert value(ROM[RSQRT.base]) == 1 and value(ROM[RSQRT.base + 48]) == 0.5
    sig = value(ROM[SIGMOID.base:SIGMOID.base + 129])
    assert np.all(np.diff(sig) >= 0)


def test_fraction_and_complement_are_exact(legal16):
    b, _ = legal16
    for fn in FUNCS:
        x = b[value(b) > 0] if fn is RSQRT else b
        i, f, omf, _ = address(fn, x)
        assert np.all((i >= 0) & (i < fn.segments))
        q = value(f).astype(np.float64)
        assert np.all(q + value(omf) == 1.0)
        assert np.all(q * 2 ** FRAC_BITS == np.floor(q * 2 ** FRAC_BITS))


def test_exact_points():
    assert list(value(exp2(f16([0, -1, -3, 5])))) == [1, 0.5, 0.125, 1]
    assert exp2(f16(-30)) == 0
    assert list(value(rsqrt(f16([1, 4, 0.25, 1024])))) == [1, 0.5, 2, 1 / 32]
    assert value(sigmoid(f16(0))) == 0.5
    assert sigmoid(f16(1000)) == ROM[SIGMOID.base + SIGMOID.segments]
    big = f16([8, 100, 60000])
    assert np.array_equal(softplus(big), big)


def _max_err(fn, ref, b, x, mask, rel):
    y, r = value(fn(b[mask])).astype(np.float64), ref(x[mask])
    e = np.abs(y - r)
    return (e / np.abs(r)).max() if rel else e.max()


def test_accuracy_exhaustive(legal16):
    b, x = legal16
    sig = lambda v: 1 / (1 + np.exp(-v))
    inr = (x >= -8) & (x <= 8)
    assert _max_err(sigmoid, sig, b, x, inr, rel=False) < 6e-4
    assert _max_err(softplus, lambda v: np.logaddexp(0, v), b, x, inr, rel=True) < 3e-3
    assert _max_err(exp2, np.exp2, b, x, (x <= 0) & (x > -13), rel=True) < 1e-3
    assert _max_err(rsqrt, lambda v: 1 / np.sqrt(v), b, x, x > 0, rel=True) < 1e-3


def test_silu_is_x_times_sigmoid():
    x = f16(np.linspace(-10, 10, 101))
    ref = to_fp16(value(x).astype(np.float64) * value(sigmoid(x)))
    assert np.array_equal(silu(x), ref)
