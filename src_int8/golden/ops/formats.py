"""Spec section 3: the one copy of the format table, plus the two rounding primitives.

A `Fmt` is a signed (or unsigned) fixed-point integer: value = int * 2^-frac, `width` bits.
`ACT` holds table 3.1 (activations and state), `PARAM` the fixed-format streamed parameters
of 3.2.  Per-row INT8 weights have no fixed scale (the row scale is carried by its RQ pair).
`rsh` and `sat` are the chip's only rounding / saturation primitives (spec section 2).
All integer arithmetic in the golden model uses int64 numpy or Python ints.
"""
from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class Fmt:
    name: str
    width: int           # total bits
    frac: int            # fraction bits: value = int * 2^-frac
    signed: bool = True

    @property
    def scale(self):
        return 2.0 ** -self.frac

    @property
    def lo(self):
        return -(1 << (self.width - 1)) if self.signed else 0

    @property
    def hi(self):
        return (1 << (self.width - 1)) - 1 if self.signed else (1 << self.width) - 1

    @property
    def dtype(self):
        return {8: np.int8, 16: np.int16, 24: np.int32, 32: np.int32}[self.width]


def _table(rows):
    return {r[0]: Fmt(*r) for r in rows}


# Table 3.1: name, width, fraction bits[, signed]
ACT = _table([
    ('X', 16, 8), ('XN', 8, 5), ('XI', 8, 4), ('XC', 16, 8), ('U', 8, 4),
    ('DL', 8, 3), ('B', 8, 5), ('C', 8, 4), ('DT_PRE', 16, 8), ('DT', 16, 12),
    ('BU', 16, 9), ('P', 32, 19), ('DA', 16, 15, False), ('H', 24, 17), ('Y', 16, 9),
    ('Z', 16, 8), ('SIG', 16, 15, False), ('SZ', 16, 8), ('G', 8, 4),
    ('MS', 32, 16, False), ('R', 16, 9), ('LOGITS', 16, 8),
])

# Table 3.2, fixed-format parameters
PARAM = _table([
    ('D', 8, 6), ('A2', 16, 7), ('CB', 16, 8), ('B_DT', 16, 8), ('E_IN', 16, 8),
])
A2_LO, A2_HI = -256.0, -(2.0 ** -7)     # A' clamp range (value), spec 3.2
W_MAX = 127                             # per-row INT8 weights use [-127, 127]

# Requant pair bounds (3.3)
M_LO, M_HI = 1 << 14, 1 << 15           # M in [2^14, 2^15)
S_LO, S_HI = 1, 47                      # s in [1, 47]

# Input activation scale (log2) of each requantised row class and its output format (3.3)
RQ_ROWS = {  # row class: (s_in format, s_out format)
    'in_x': ('XN', 'XI'), 'conv': ('XI', 'XC'), 'dl': ('U', 'DL'), 'b': ('U', 'B'),
    'c': ('U', 'C'), 'dt': ('DL', 'DT_PRE'), 'z': ('XN', 'Z'), 'out': ('G', 'X'),
    'logits': ('XN', 'LOGITS'),
}

DT_MAX = ACT['DT'].hi                   # softplus output saturates at 8 - 2^-12
EXP2_ZERO_P = -16 << ACT['P'].frac      # p <= -16 -> dA = 0
EPS_INIT = 16                           # 2^-12 in Q.16: RMSNorm accumulator init


def rsh(v, k):
    """Round half up and arithmetic shift: (v + 2^(k-1)) >> k; rsh(v, 0) = v."""
    assert 0 <= k < 63
    v = np.asarray(v, dtype=np.int64)
    if k == 0:
        return v
    return (v + (np.int64(1) << np.int64(k - 1))) >> np.int64(k)


def sat(v, w):
    """Clamp to the signed w-bit range; w = 32 passes through (raw)."""
    v = np.asarray(v, dtype=np.int64)
    if w == 32:
        return v
    lim = np.int64(1) << np.int64(w - 1)
    return np.clip(v, -lim, lim - 1)


def fits(v, bits, signed=True):
    """True if every element is representable in `bits` bits."""
    v = np.asarray(v, dtype=np.int64)
    if signed:
        lim = 1 << (bits - 1)
        return bool(np.all((v >= -lim) & (v < lim)))
    return bool(np.all((v >= 0) & (v < (1 << bits))))
