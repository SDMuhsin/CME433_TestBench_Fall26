"""AND-array partial products: unsigned and signed (modified Baugh-Wooley) n x n."""
from .matrix import BitMatrix


def and_grid(net, a, b):
    """g[m][k] = a_m b_k (the paper's a_{m,k}), wires named pp_m_k."""
    return [[net.name(net.AND(am, bk), f'pp_{m}_{k}') for k, bk in enumerate(b)]
            for m, am in enumerate(a)]


def column_order(n, col):
    """(m, k) index pairs of column `col` in the drawing order of Venkatachalam & Ko Fig. 1:
    the symmetric pairs (m, k), (k, m) with m > k by decreasing m, then the diagonal."""
    pairs = [(m, col - m) for m in range(n - 1, -1, -1) if 0 <= col - m < m]
    out = [x for m, k in pairs for x in ((m, k), (k, m))]
    if col % 2 == 0 and col // 2 < n:
        out.append((col // 2, col // 2))
    return out


def unsigned(net, a, b):
    n = len(a)
    g = and_grid(net, a, b)
    mat = BitMatrix(net, 2 * n)
    for col in range(2 * n - 1):
        for m, k in column_order(n, col):
            mat.add(col, g[m][k])
    return mat


def baugh_wooley(net, a, b):
    """Signed (two's complement) a x b: a_m b_k is negative iff exactly one of m, k is the
    sign bit; stored inverted with the constant 2^n + 2^(2n-1) (mod 2^2n). Columns list the
    bits by multiplier row k (b bit), as in an array drawing."""
    n = len(a)
    g = and_grid(net, a, b)
    mat = BitMatrix(net, 2 * n)
    for k in range(n):
        for m in range(n):
            mat.add(m + k, g[m][k], negative=(m == n - 1) != (k == n - 1))
    return mat
