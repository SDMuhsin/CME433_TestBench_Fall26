"""Aizaz & Khare, "Area and Power Efficient Truncated Booth Multipliers Using Approximate
Carry-Based Error Compensation", IEEE TCAS-II 69(2):579-583, 2022 (TACBM).

Signed n x n radix-4 Booth multiplier (booth.py front end) with
* truncation factor w: the w least significant columns (0 .. w-1) are not generated, so
  product bits 0 .. w-1 are 0 (Fig. 2(b), w = 10: columns #1-#10 truncated);
* approximate compensation carries t^k_w (eqs. 1-5): the partial products P_{i,j} of column
  w-1 (P_{i,j} = bit j of Booth row i, at column 2i + j) are not summed but feed small
  AND / OR terms that approximate the carry C_w into column w while ignoring C_{w-1}
  (k-map with flipped bits, Table II). The terms of one w are mutually exclusive; each is one
  extra bit of column w, so `terms` (1-based indices) selects the subsets of Table III;
* "the neg terms [7] and the preceding partial product are ORed together" (Fig. 2(b), the
  black squares at columns 2i): the Booth +1 bit neg_i and the row's first bit P_{i,0} become
  one bit P_{i,0} OR neg_i (wrong by -2^(2i) when both are 1). `neg_or=False` keeps them exact;
* the remaining matrix is reduced with exact cells (Dadda) and one carry-propagate adder.
The paper gives the terms for w = 4 .. 12 only (w = 14 is in Table IV but not written out).
"""
from . import booth
from .cells import EXACT
from .matrix import BitMatrix
from .mult import build
from .netlist import Net

N = 16


def _terms(net, P, w):
    """Compensation carries t^1_w, t^2_w, ... of eqs. (1)-(5); P(i, j) is a column-(w-1) bit."""
    A, O, X = net.AND, net.OR, net.NOT

    def all_(*xs):
        out = xs[0]
        for x in xs[1:]:
            out = A(out, x)
        return out

    if w == 4:
        return [P(0, 3)]
    if w == 6:
        return [O(P(0, 5), A(P(1, 3), P(2, 1)))]
    if w == 8:
        p0, p1, p2, p3 = P(0, 7), P(1, 5), P(2, 3), P(3, 1)
        return [A(X(p0), O(p1, A(p2, p3))),
                A(p0, O(X(p1), A(X(p2), X(p3))))]
    if w == 10:
        p0, p1, p2, p3, p4 = P(0, 9), P(1, 7), P(2, 5), P(3, 3), P(4, 1)
        return [all_(O(p2, A(p3, p4)), X(p0), X(p1)),
                A(net.XOR(p0, p1), O(X(p2), A(X(p3), X(p4)))),
                all_(O(X(p3), X(p4)), p0, p1, X(p2))]
    if w == 12:
        p0, p1, p2, p3, p4, p5 = P(0, 11), P(1, 9), P(2, 7), P(3, 5), P(4, 3), P(5, 1)
        one_of = net.any([all_(X(p0), X(p1), p2), all_(X(p0), p1, X(p2)), all_(p0, X(p1), X(p2))])
        two_of = net.any([all_(X(p0), p1, p2), all_(p0, X(p1), p2), all_(p0, p1, X(p2))])
        return [A(O(X(p3), A(X(p4), X(p5))), one_of),
                all_(O(p3, A(p4, p5)), X(p0), X(p1), X(p2)),
                all_(X(p3), O(X(p4), X(p5)), two_of),
                all_(p0, p1, p2, p5, O(p3, p4))]
    raise ValueError(f'TACBM terms are published for w = 4, 6, 8, 10, 12 only (got {w})')


def matrix(net, a, b, w, terms=None, neg_or=True, strict_neg=True, const=0):
    """Truncated Booth matrix (columns >= w) plus the compensation terms in column w.
    terms: None = all published terms, a tuple of 1-based indices = that subset, () = none.
    const: an integer added to the matrix instead (constant compensation, e.g. 1 << w).
    strict_neg: Booth digit 111 gives neg = 0 (only used with neg_or, see booth.encode)."""
    n = len(a)
    mat = BitMatrix(net, 2 * n)
    col = {}                                      # (i, j) -> bit of column w - 1
    for i, digit in enumerate(booth.encode(net, b, strict_neg and neg_or)):
        bits = booth.row_bits(net, a, digit, i)
        neg = digit[2]
        if neg_or:
            bits[0] = net.name(net.OR(bits[0], neg), f'bpn_{i}')
        elif 2 * i >= w:
            mat.add(2 * i, neg)
        for j, bit in enumerate(bits):
            c = 2 * i + j
            if c == w - 1:
                col[(i, j)] = bit
            if c >= w:
                mat.add(c, bit, negative=(j == n))
    mat.add_const(const)
    if w == 0 or terms == ():
        return mat
    ts = _terms(net, lambda i, j: col[(i, j)], w)
    for k, t in enumerate(ts, 1):
        if terms is None or k in terms:
            mat.add(w, net.name(t, f't{k}_{w}'))
    return mat


def tacbm(n=N, w=10, terms=None, neg_or=True, strict_neg=True):
    """Signed n x n TACBM (Python model + netlist)."""
    net = Net()
    a, b = net.bus('a', n), net.bus('b', n)
    cols = matrix(net, a, b, w, terms, neg_or, strict_neg).columns()
    return build(net, a, b, cols, lambda i: EXACT, signed=True)
