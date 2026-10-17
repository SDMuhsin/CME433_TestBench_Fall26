"""A structured multiplier = netlist + two final rows (x, y) added by one carry-propagate
adder, and its bit-exact Python evaluation over integer operand arrays."""
from dataclasses import dataclass, field
from collections import Counter

import numpy as np

from .netlist import Net
from .reduce import DADDA, default_order, reduce


@dataclass
class Multiplier:
    net: Net
    n: int                     # operand width; product width 2n
    signed: bool
    x: list
    y: list
    log: list = field(default_factory=list)

    def cell_count(self):
        """{cell name: count} over the reduction tree."""
        return Counter(name for _, _, name in self.log)

    def products(self, a, b):
        """Products for operand arrays a, b (same shape, values in the operand range)."""
        a = np.asarray(a, np.int64).ravel()
        b = np.asarray(b, np.int64).ravel()
        bits = {'a': _pack(a, self.n), 'b': _pack(b, self.n)}
        ones = np.uint64(0xFFFFFFFFFFFFFFFF)
        x, y = self.net.evaluate(bits, [self.x, self.y], ones)
        w = 2 * self.n
        p = (_unpack(x, a.size) + _unpack(y, a.size)) & ((1 << w) - 1)
        if self.signed:
            p = np.where(p >= 1 << (w - 1), p - (1 << w), p)
        return p


def build(net, a, b, cols, cells_of, seq=DADDA, signed=False, order=default_order):
    x, y, log = reduce(net, cols, cells_of, seq, order)
    return Multiplier(net, len(a), signed, x, y, log)


def _pack(v, n):
    """Bit planes of v, 64 operands per uint64 word (bit i of plane j = bit j of v[i])."""
    pad = (-v.size) % 64
    out = []
    for j in range(n):
        bit = ((v >> j) & 1).astype(np.uint8)
        out.append(np.packbits(np.concatenate([bit, np.zeros(pad, np.uint8)]),
                               bitorder='little').view(np.uint64))
    return out


def _unpack(planes, size):
    val = np.zeros(size, np.int64)
    for j, pl in enumerate(planes):
        if np.ndim(pl) == 0:              # constant column bit
            if int(pl):
                val += 1 << j
            continue
        bit = np.unpackbits(pl.view(np.uint8), bitorder='little')[:size]
        val += bit.astype(np.int64) << j
    return val
