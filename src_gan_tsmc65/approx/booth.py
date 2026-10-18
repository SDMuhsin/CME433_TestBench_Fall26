"""Radix-4 (modified) Booth multiplier front end, signed n x n with n even.

The multiplier b is recoded into n/2 digits d_i in {-2..2} from (b_{2i+1}, b_{2i}, b_{2i-1});
row i is d_i * a as an (n+1)-bit two's-complement word at column 2i: bits
pp_ij = ((one_i a_j) | (two_i a_{j-1})) xor neg_i, plus the +1 correction neg_i at column 2i.
The row sign bit pp_in has negative weight (stored inverted with a constant, see matrix.py).
"""
from .matrix import BitMatrix
from .netlist import ZERO


def encode(net, b, strict_neg=False):
    """Booth digits as (one, two, neg) per digit i (|d| = 1, |d| = 2, d < 0). By default
    neg = b_{2i+1}, so the digit 111 is "-0" (row of ones + 1); strict_neg makes neg = 0 for it
    (one more gate per digit; matters only when the neg bit is approximated)."""
    out = []
    for i in range(len(b) // 2):
        lo = b[2 * i - 1] if i else ZERO
        mid, hi = b[2 * i], b[2 * i + 1]
        one = net.XOR(mid, lo)
        two = net.AND(net.XOR(hi, mid), net.NOT(one))
        neg = net.AND(hi, net.NOT(net.AND(mid, lo))) if strict_neg else hi
        out.append((net.name(one, f'bd{i}_one'), net.name(two, f'bd{i}_two'),
                    net.name(neg, f'bd{i}_neg')))
    return out


def row_bits(net, a, digit, i):
    """The n+1 bits of row i (LSB first); a is sign-extended by one bit."""
    one, two, neg = digit
    ax = list(a) + [a[-1]]
    bits = []
    for j in range(len(ax)):
        prev = ax[j - 1] if j else ZERO
        mag = net.OR(net.AND(one, ax[j]), net.AND(two, prev))
        bits.append(net.name(net.XOR(mag, neg), f'bpp_{i}_{j}'))
    return bits


def matrix(net, a, b):
    n = len(a)
    mat = BitMatrix(net, 2 * n)
    for i, digit in enumerate(encode(net, b)):
        bits = row_bits(net, a, digit, i)
        for j, bit in enumerate(bits):
            mat.add(2 * i + j, bit, negative=(j == n))
        mat.add(2 * i, digit[2])
    return mat
