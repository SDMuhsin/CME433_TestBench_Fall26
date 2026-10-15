"""Shared nonlinear unit: one FP16 ROM + linear interpolation on the MAC lane (spec section 4).

Each function maps its FP16 input to (ROM index i, fraction f, output scale s); the result is
writeback(T[i] * (1 - f) + T[i+1] * f, s), with f = k / 2^FRAC_BITS so f and 1 - f are exact FP16.
  uniform  sigmoid, softplus: x clamped to [lo, hi], u = (x - lo) * 2^k
  exp2     x <= 0 (x > 0 clamps to 0): u = frac(x) * 2^k, s = floor(x)
  rsqrt    x = m * 2^e, m in [1, 4), e even: u = (m - 1) * 2^k, s = -e / 2
"""
from dataclasses import dataclass

import numpy as np

from .fp import dot, mul, to_fp16, value, writeback

FRAC_BITS = 11


@dataclass(frozen=True)
class LutFunc:
    name: str
    mode: str        # 'uniform' | 'exp2' | 'rsqrt'
    lo: float        # grid origin
    k: int           # grid step 2^-k
    segments: int
    base: int        # first ROM word
    ref: object      # float64 reference on the grid

    @property
    def grid(self):
        return self.lo + np.arange(self.segments + 1) / 2.0 ** self.k

    @property
    def hi(self):
        return self.lo + self.segments / 2.0 ** self.k


def _softplus(x):
    return np.logaddexp(0.0, x)


SIGMOID = LutFunc('sigmoid', 'uniform', -8.0, 3, 128, 0, lambda x: 0.5 * (1 + np.tanh(x / 2)))
SOFTPLUS = LutFunc('softplus', 'uniform', -8.0, 3, 128, 129, _softplus)
EXP2 = LutFunc('exp2', 'exp2', 0.0, 5, 32, 258, np.exp2)
RSQRT = LutFunc('rsqrt', 'rsqrt', 1.0, 4, 48, 291, lambda m: 1.0 / np.sqrt(m))
FUNCS = (SIGMOID, SOFTPLUS, EXP2, RSQRT)
ROM_WORDS = RSQRT.base + RSQRT.segments + 1


def build_rom():
    """ROM image: per function, FP16(ref(grid point)) for segments + 1 grid points."""
    rom = np.zeros(ROM_WORDS, dtype=np.uint16)
    for fn in FUNCS:
        rom[fn.base:fn.base + fn.segments + 1] = to_fp16(fn.ref(fn.grid))
    return rom


ROM = build_rom()


def _split(u, segments):
    """Grid coordinate u >= 0 -> (segment index, FP16 bits of f, FP16 bits of 1 - f)."""
    i = np.minimum(np.floor(u), segments - 1)
    q = np.floor((u - i) * 2 ** FRAC_BITS) / 2 ** FRAC_BITS
    return i.astype(np.int64), to_fp16(q), to_fp16(1.0 - q)


def address(fn, x_bits):
    """FP16 input -> (i, f bits, 1-f bits, scale) for one LUT function (exact integer math)."""
    x = value(x_bits).astype(np.float64)
    scale = np.zeros(x.shape, dtype=np.int64)
    if fn.mode == 'uniform':
        u = (np.clip(x, fn.lo, fn.hi) - fn.lo) * 2.0 ** fn.k
    elif fn.mode == 'exp2':
        p = np.minimum(x, 0.0)
        scale = np.floor(p).astype(np.int64)
        u = (p - scale) * 2.0 ** fn.k
    else:
        assert np.all(x > 0), 'rsqrt input must be positive'
        m, e = np.frexp(x)                      # x = m 2^e, m in [0.5, 1)
        odd = (e - 1) % 2 != 0
        m = np.where(odd, 4 * m, 2 * m)         # m in [1, 4)
        ev = np.where(odd, e - 2, e - 1)        # even exponent
        scale = -(ev // 2)
        u = (m - 1.0) * 2.0 ** fn.k
    i, f, omf = _split(u, fn.segments)
    return i, f, omf, scale


def lut(fn, x_bits):
    """Evaluate one ROM function on FP16 bits (interpolation runs as two lane MACs)."""
    i, f, omf, scale = address(fn, x_bits)
    acc = dot([(ROM[fn.base + i], omf), (ROM[fn.base + i + 1], f)])
    out = writeback(acc, scale)
    if fn is SOFTPLUS:
        out = np.where(value(x_bits) >= fn.hi, x_bits, out).astype(np.uint16)
    return out


def sigmoid(x):
    return lut(SIGMOID, x)


def softplus(x):
    return lut(SOFTPLUS, x)


def exp2(x):
    return lut(EXP2, x)


def rsqrt(x):
    return lut(RSQRT, x)


def silu(x):
    """SiLU(x) = FP16(x * sigmoid(x))."""
    return mul(x, sigmoid(x))

