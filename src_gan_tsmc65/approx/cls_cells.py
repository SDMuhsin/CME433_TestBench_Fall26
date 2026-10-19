"""Cells of Wang et al. 2026 (CLS-driven classified truncation approximate Booth, TVLSI 34(9)).

Encoders map one radix-4 Booth group (b_2i+1, b_2i, b_2i-1) = (hi, mid, lo) and the
multiplicand bit a_j to the partial-product bit pp_ij (the exact bit would also need a_j-1):
  cae1  eq. (4) / Fig. 3, as in the authors' RTL:
        hi ~mid (~lo | ~a_j) | ~hi a_j (mid | lo); 6 of the 32 K-map entries flipped
        (digit +2 -> a_j instead of a_j-1, -2 -> 1, the 110 form of -1 -> 0)
  cae2  eq. (5) / Fig. 4: a_j xor hi (8 entries flipped)
Approximate 4:2 compressors without cin / cout, (x1, x2, x3, x4) -> (sum, carry), Table II:
  a4t2c1  eq. (6): sum = x2 (x1 | ~(x3 xor x4)), carry = x3 | x4 (the printed eq. lost the
          overbar; this form is the authors' RTL and reproduces Table II)
  a4t2c2  eq. (7): sum = x1 | x2 | x3 | x4, carry = x2 (x3 | x4)
`zero_safe` variants (not in the paper) gate the encoder with OR(hi, mid, lo), so the digit 000
gives a zero bit (b = 0 -> zero rows).
"""


def cae1(net, hi, mid, lo, aj):
    neg = net.AND(hi, net.AND(net.NOT(mid), net.OR(net.NOT(lo), net.NOT(aj))))
    pos = net.AND(net.NOT(hi), net.AND(aj, net.OR(mid, lo)))
    return net.OR(neg, pos)


def cae2(net, hi, mid, lo, aj):
    return net.XOR(aj, hi)


def cae2_zero_safe(net, hi, mid, lo, aj):
    return net.AND(net.XOR(aj, hi), net.any([hi, mid, lo]))


def a4t2c1(net, x1, x2, x3, x4):
    return net.AND(x2, net.OR(x1, net.NOT(net.XOR(x3, x4)))), net.OR(x3, x4)


def a4t2c2(net, x1, x2, x3, x4):
    return net.any([x1, x2, x3, x4]), net.AND(x2, net.OR(x3, x4))


ENCODERS = {'cae1': cae1, 'cae2': cae2, 'cae2z': cae2_zero_safe}
COMPRESSORS = {'a4t2c1': a4t2c1, 'a4t2c2': a4t2c2}
