"""Partial-product bit matrix: columns of single-bit signals plus one integer constant.

A bit with negative weight (two's-complement sign terms) is stored inverted and its weight is
moved into the constant: -x 2^k = (not x) 2^k - 2^k. `columns()` folds the constant (mod 2^width)
into constant-1 bits at the bottom of their columns, so every signed scheme (Baugh-Wooley,
Booth sign extension) ends up as a plain unsigned dot diagram.
"""
from .netlist import ONE


class BitMatrix:
    def __init__(self, net, width):
        self.net, self.width = net, width
        self.cols = [[] for _ in range(width)]
        self.const = 0

    def add(self, col, bit, negative=False):
        if col >= self.width:
            return
        if negative:
            bit = self.net.NOT(bit)
            self.const -= 1 << col
        self.cols[col].append(bit)

    def add_const(self, value):
        self.const += value

    def columns(self):
        cols = [list(c) for c in self.cols]
        k = self.const % (1 << self.width)
        for i in range(self.width):
            if (k >> i) & 1:
                cols[i].append(ONE)
        return cols
