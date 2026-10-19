"""Zhu, Zhen, Yi, Pei, Hou & He, "Design of Approximate Radix-256 Booth Encoding for
Error-Tolerant Computing", IEEE TCAS-II 69(4):2286-2290, 2022.

Signed n x n hybrid Booth multiplier (b = Y recoded, a = X the multiplicand), Fig. 1:
* the d least significant bits of b (d = 8 in the paper: one radix-256 digit, y_-1 = 0) form one
  approximate digit (AR256, Table III): only its top 4 bits t = y_d-1..y_d-4 are encoded and
  the digit is replaced by P = +-(A + B) X 2^(d-8), A in {0, 16, 32, 64}, B in {8, 16, 32, 64}
  (r256.py); two rows PPA / PPB of eq. (8), each XOR-ed with c = y_d-1 (one's complement),
  plus the correction bits c;
* the remaining n - d bits use exact radix-4 Booth (booth.py), (n - d) / 2 rows, the first
  digit overlapping y_d-1;
* sign extension by constant (matrix.py; the same value as the 1 / ~E bits of Fig. 1), one
  group of exact 4:2 compressors (park_tree.py: "the same compression tree with exact 4-2
  compressors" as the paper's exact radix-4 ACR4) and one carry-propagate adder.
The paper's PPA_j / PPB_j for j below the row's smallest shift are 0 xor c = c; with the
correction c at column 0 they sum to c 2^shift, so the correction bit is placed at the row's
smallest shift instead (identical value, no constant-0 columns).
`zero_fix` (not in the paper): B_8M is gated by OR(y_0..y_d-1), so b = 0 gives 0 (r256.py).
"""
import numpy as np

from . import booth, r256
from .matrix import BitMatrix
from .mult import Multiplier
from .netlist import Net
from .park_tree import reduce


def _ar_rows(net, mat, a, b, d, zero_fix):
    """PPA / PPB of eq. (8) for the AR digit of b[0:d] into the bit matrix."""
    n = len(a)
    sel_a, sel_b = r256.encoder(net, b[d - 4:d], b[:d] if zero_fix else None)
    c = b[d - 1]
    top = n + d - 3                                  # sign column of 64M X 2^(d-8)
    for tag, sel in (('a', sel_a), ('b', sel_b)):
        shifts = {r256.shift(m, d): s for m, s in sel.items()}
        lo = min(shifts)
        for j in range(lo, top + 1):
            terms = [net.AND(s, a[min(j - k, n - 1)]) for k, s in shifts.items() if j >= k]
            bit = net.name(net.XOR(net.any(terms), c), f'pp{tag}_{j}')
            mat.add(j, bit, negative=(j == top))
        mat.add(lo, c)


def _r4_rows(net, mat, a, b, d):
    n = len(a)
    for i, digit in enumerate(booth.encode(net, b)):
        if 2 * i < d:
            continue
        for j, bit in enumerate(booth.row_bits(net, a, digit, i)):
            mat.add(2 * i + j, bit, negative=(j == n))
        mat.add(2 * i, digit[2])


def zhu(n=16, d=8, zero_fix=False):
    """Signed n x n AR256 hybrid multiplier (netlist + Python model, mult.Multiplier)."""
    assert d % 2 == 0 and 6 <= d <= n
    net = Net()
    a, b = net.bus('a', n), net.bus('b', n)
    mat = BitMatrix(net, 2 * n)
    _ar_rows(net, mat, a, b, d, zero_fix)
    _r4_rows(net, mat, a, b, d)
    x, y, log = reduce(net, [mat.columns()], 0)
    return Multiplier(net, n, True, x, y, log)


class Model:
    """Closed-form reference: p = a (b - b_lo + P(b_lo)), b_lo = signed value of b[0:d]."""

    def __init__(self, n=16, d=8, zero_fix=False):
        self.n, self.d, self.zero_fix, self.signed = n, d, zero_fix, True

    def products(self, a, b):
        a, b = np.asarray(a, np.int64), np.asarray(b, np.int64)
        lo = b & ((1 << self.d) - 1)
        lo = np.where(lo >= 1 << (self.d - 1), lo - (1 << self.d), lo)
        return a * (b - lo + r256.digit(lo, self.d, self.zero_fix))
