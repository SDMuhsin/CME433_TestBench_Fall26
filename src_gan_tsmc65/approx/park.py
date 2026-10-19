"""Park, Kung & Lee, "Simplified Compressor and Encoder Designs for Low-Cost Approximate Radix-4
Booth Multiplier", IEEE TCAS-II 70(3):1154-1158, 2023.

Signed n x n radix-4 Booth multiplier (b recoded, n/2 rows) with
* the exact Booth bits of eq. (1) (booth.py with the strict neg: digit 111 gives a zero row);
* the approximate encoder p~_ij = a_j | b_2i+1 (Table I, one OR gate) for every data bit in the
  wG least significant columns (the sign-related bits stay exact);
* sign extension as in Fig. 1: row 0 E E ~E, rows i > 0 ~E 1 (E = the row's sign bit);
* neg_i (the +1 of a negative digit) at column 2i in the first row group with room (< 4 bits);
  the last row's neg is OR-ed with its first bit (the filled square OR(Neg, PP) of Fig. 1),
  which keeps every group four bits high (`neg_or=False` adds it as a separate bit instead);
* the grouped 4:2 reduction of park_tree.py with the approximate compressor (eq. 3) in the wA
  least significant columns, and one carry-propagate adder.
`zero_fix` (not in the paper): p~_ij = b_2i+1 | a_j (b_2i | b_2i-1), so a zero digit gives a
zero row and b = 0 gives an exact 0 (the paper's encoder gives a_j for the digit 000).
"""
from . import booth
from .mult import Multiplier
from .netlist import ONE, ZERO, Net
from .park_tree import reduce

GROUP = 4                      # rows per first-stage group (4:2 compressors)


def rows(net, a, b, wg, zero_fix=False, neg_or=True):
    """Booth rows as [(column, bit)] lists and the neg bits as [(column, bit)]."""
    n = len(a)
    out, negs = [], []
    digits = booth.encode(net, b, strict_neg=True)
    for i, digit in enumerate(digits):
        bits = booth.row_bits(net, a, digit, i)
        hi = b[2 * i + 1]
        z = net.OR(b[2 * i], b[2 * i - 1] if i else ZERO)
        for j in range(n):
            if 2 * i + j < wg:
                t = net.AND(a[j], z) if zero_fix else a[j]
                bits[j] = net.name(net.OR(t, hi), f'pa_{i}_{j}')
        e = bits[n]
        if i == 0:
            sign = [(n, e), (n + 1, e), (n + 2, net.NOT(e))]
        else:
            sign = [(2 * i + n, net.NOT(e)), (2 * i + n + 1, ONE)]
        neg = digit[2]
        if neg_or and i == len(digits) - 1:
            bits[0] = net.name(net.OR(bits[0], neg), f'pn_{i}')
        else:
            negs.append((2 * i, neg))
        out.append([(2 * i + j, bits[j]) for j in range(n)] + sign)
    return out, negs


def groups(rows_, negs, width):
    """First-stage groups of GROUP rows; each neg goes to the first group with < GROUP bits."""
    gs = [[[] for _ in range(width)] for _ in range(max(1, len(rows_) // GROUP))]
    for i, row in enumerate(rows_):
        g = gs[min(i // GROUP, len(gs) - 1)]
        for c, bit in row:
            if c < width:
                g[c].append(bit)
    for c, bit in negs:
        g = next((g for g in gs if len(g[c]) < GROUP), gs[-1])
        g[c].append(bit)
    return gs


def park(n=16, wg=0, wa=0, zero_fix=False, neg_or=True):
    """Signed n x n Park 2023 multiplier (netlist + Python model, mult.Multiplier)."""
    net = Net()
    a, b = net.bus('a', n), net.bus('b', n)
    r, negs = rows(net, a, b, wg, zero_fix, neg_or)
    x, y, log = reduce(net, groups(r, negs, 2 * n), wa)
    return Multiplier(net, n, True, x, y, log)
