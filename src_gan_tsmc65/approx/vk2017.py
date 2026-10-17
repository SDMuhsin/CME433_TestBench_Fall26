"""Venkatachalam & Ko, "Design of Power and Area Efficient Approximate Multipliers",
IEEE TVLSI 25(5):1782-1786, 2017: unsigned n x n multipliers with altered partial products.

* Columns with more than three partial products: each pair a_{m,k}, a_{k,m} (m > k) becomes
  p_{m,k} = a_{m,k} + a_{k,m} (OR) and g_{m,k} = a_{m,k} a_{k,m} (AND), eq. (1); exact since
  a + b = (a | b) + (a & b). The g's of a column are OR-ed in ceil(m/4) gates (G_i), Sec. II-A.
* The rest is reduced with the approximate HA / FA / 4:2 compressor (cells.py) in Dadda
  stages (reduce.py, sequence 2, 3, 6, ...), then one exact carry-propagate adder.
* Multiplier1: approximate in all columns. Multiplier2: approximate in the n - 1 least
  significant columns; the upper columns keep the plain a_{m,k} and exact HA / FA.
For n = 8 Multiplier1 gives exactly the dot diagram of Fig. 2 (stage 1: 3 HA, 3 FA, 3 4:2,
OR2 x4, OR3 x4, OR4 x1; stage 2: 1 HA, 11 FA).
"""
from math import ceil

from .cells import EXACT, VK_ALL
from .mult import build
from .netlist import Net
from .pp import and_grid, column_order
from .reduce import DADDA_C42, default_order


def _groups(xs, size=4):
    k = ceil(len(xs) / size)
    cut = [len(xs) * j // k for j in range(k + 1)]
    return [xs[cut[j]:cut[j + 1]] for j in range(k)]


def altered_column(net, g, n, col):
    order = column_order(n, col)
    pairs = [(order[j], order[j + 1]) for j in range(0, len(order) - 1, 2)
             if order[j][0] != order[j][1]]
    ps = [net.name(net.OR(g[m][k], g[k][m]), f'p_{m}_{k}') for (m, k), _ in pairs]
    gs = [net.name(net.AND(g[m][k], g[k][m]), f'g_{m}_{k}') for (m, k), _ in pairs]
    diag = [g[m][k] for m, k in order if m == k]
    big_g = [net.name(net.any(grp), f'G{col}_{j}') for j, grp in enumerate(_groups(gs))]
    return ps + diag + big_g


def fig2_order(stage, col, sums, rest, carries):
    """Stage-2 operand order as drawn in Fig. 2 for n = 8: column 12 is S12, C11, a6,6 (the
    default rule would give S12, a6,6, C11); every other column already matches the drawing."""
    if stage == 1 and col == 12:
        return sums + carries + rest
    return default_order(stage, col, sums, rest, carries)


def multiplier(n, approx_cols):
    """Unsigned n x n; columns < approx_cols are approximate (2n: Multiplier1, n-1: Multiplier2).
    n = 8 uses the exact operand order of Fig. 2; other n use the default rule of reduce.py."""
    net = Net()
    a, b = net.bus('a', n), net.bus('b', n)
    g = and_grid(net, a, b)
    cols = []
    for col in range(2 * n):
        order = column_order(n, col)
        if col < approx_cols and len(order) > 3:
            cols.append(altered_column(net, g, n, col))
        else:
            cols.append([g[m][k] for m, k in order])
    return build(net, a, b, cols, lambda i: VK_ALL if i < approx_cols else EXACT, DADDA_C42,
                 order=fig2_order if n == 8 else default_order)


def multiplier1(n=8):
    return multiplier(n, 2 * n)


def multiplier2(n=8):
    return multiplier(n, n - 1)
