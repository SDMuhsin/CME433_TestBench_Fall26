"""Spec section 5.1: the shared nonlinear unit. One 340 x 16-bit ROM, four functions,
linear interpolation as two lane MACs, integer address arithmetic.

  Sigma = T[i] * (2^11 - f) + T[i+1] * f ;  out = sh_16(Sigma, sh_fn)

The ROM contents are host-side constants (float64 at build time, then integers); everything
at run time is int64 integer arithmetic.
"""
from dataclasses import dataclass

import numpy as np

from .formats import ACT, EXP2_ZERO_P, rsh, sat
from .lane import mac

FRAC_BITS = 11
FRAC_ONE = 1 << FRAC_BITS
I64 = np.int64


def _round(x):
    """Round half up to an integer array (table generation only)."""
    return np.floor(np.asarray(x, dtype=np.float64) + 0.5).astype(I64)


@dataclass(frozen=True)
class LutFunc:
    name: str
    base: int          # first ROM word
    segments: int      # words = segments + 1
    table: object      # j array -> exact integer table values

    @property
    def words(self):
        return self.segments + 1

    @property
    def end(self):
        return self.base + self.words


def _sigmoid_table(j):
    return _round(1 / (1 + np.exp(-(-8 + j / 8))) * 2 ** 15)


def _softplus_table(j):
    return np.minimum(_round(np.logaddexp(0, -8 + j / 8) * 2 ** 12), 32767)


def _exp2_table(j):
    return _round(np.exp2(j / 32) * 2 ** 14)


def _rsqrt_table(j):
    return _round(2 ** 14 / np.sqrt(1 + j / 16))


SIGMOID = LutFunc('sigmoid', 0, 128, _sigmoid_table)
SOFTPLUS = LutFunc('softplus', 129, 128, _softplus_table)
EXP2 = LutFunc('exp2', 258, 32, _exp2_table)
RSQRT = LutFunc('rsqrt', 291, 48, _rsqrt_table)
FUNCS = (SIGMOID, SOFTPLUS, EXP2, RSQRT)
ROM_WORDS = RSQRT.end


def build_rom():
    rom = np.zeros(ROM_WORDS, dtype=I64)
    for fn in FUNCS:
        rom[fn.base:fn.end] = fn.table(np.arange(fn.words))
    assert np.all((rom >= 0) & (rom < 1 << 16))
    return rom


ROM = build_rom()


# --- address arithmetic: input -> (i, f, sh_fn, zero flag) ----------------------------------

def addr_uniform(x):
    """sigmoid / softplus: x INT32 read as Q7.8."""
    x = np.clip(np.asarray(x, dtype=I64), -2048, 2048)
    u = x + 2048
    i = np.minimum(u >> 5, 127)
    f = (u - 32 * i) << 6
    return i, f, np.full(x.shape, 11, dtype=I64), np.zeros(x.shape, dtype=bool)


def addr_exp2(p):
    """p INT32 read as Q11.19; p >= 0 -> 0; p <= -16 -> zero flag."""
    p = np.minimum(np.asarray(p, dtype=I64), 0)
    zero = p <= EXP2_ZERO_P
    e = np.maximum(p >> 19, -16)                     # floor; the clamp only affects zero-flagged inputs
    frac = p & ((1 << 19) - 1)
    i = frac >> 14
    f = (frac >> 3) & 0x7FF
    return i, f, 10 - e, zero


def _floor_log2(n):
    """Bit length minus one of positive int64 values, in integer arithmetic."""
    b = np.zeros(n.shape, dtype=I64)
    for k in range(1, 32):
        b += (n >> k) > 0
    return b


def addr_rsqrt(n):
    """n UINT32 read as Q.16, n >= 16."""
    n = np.asarray(n, dtype=I64)
    assert np.all((n >= 16) & (n < 1 << 31)), 'rsqrt input range'
    E = _floor_log2(n) - 16
    E = E - (E & 1)                                   # make even (decrement odd values)
    m16 = np.where(E >= 0, n >> np.maximum(E, 0), n << np.maximum(-E, 0))
    u = m16 - (1 << 16)
    i = u >> 12
    f = (u >> 1) & 0x7FF
    return i, f, 16 + E // 2, np.zeros(n.shape, dtype=bool)


ADDR = {SIGMOID: addr_uniform, SOFTPLUS: addr_uniform, EXP2: addr_exp2, RSQRT: addr_rsqrt}


def lerp(fn, i, f, shift):
    """Two lane MACs (ps 0, init 0) and the function's writeback shift, saturated to 16 bits."""
    acc = mac(0, ROM[fn.base + i], FRAC_ONE - f, 0)
    acc = mac(acc, ROM[fn.base + i + 1], f, 0)
    shift = np.asarray(shift, dtype=I64)
    out = np.empty(acc.shape, dtype=I64)
    for k in np.unique(shift):                        # rsh takes a scalar shift
        m = shift == k
        out[m] = sat(rsh(acc[m], int(k)), 16)
    return out


def lut(fn, x):
    i, f, shift, zero = ADDR[fn](x)
    return np.where(zero, 0, lerp(fn, i, f, shift))


def sigmoid(x):
    """x Q7.8 (any INT32) -> SIG Q0.15."""
    return lut(SIGMOID, x)


def softplus(x):
    """x Q7.8 (any INT32) -> DT Q3.12 in [0, 8 - 2^-12]."""
    return lut(SOFTPLUS, x)


def exp2(p):
    """p Q11.19 (INT32) -> DA Q0.15 (0 for p <= -16, 32767 for p = 0)."""
    return lut(EXP2, p)


def rsqrt(n):
    """n Q.16 (UINT32, >= 16) -> R Q6.9."""
    return lut(RSQRT, n)


def silu16(x):
    """SiLU of a Q7.8 value: sh_16(x * sigmoid(x), 15) -> Q7.8."""
    return sat(rsh(mac(0, x, sigmoid(x), 0), 15), 16)


assert ACT['SIG'].frac == 15 and ACT['DT'].frac == 12 and ACT['DA'].frac == 15 and ACT['R'].frac == 9
