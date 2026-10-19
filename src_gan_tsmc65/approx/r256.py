"""Approximate radix-256 (AR256) Booth digit of Zhu et al., IEEE TCAS-II 69(4) 2022, Table III.

The 9-bit set y_7..y_0 y_-1 of a radix-256 digit is split into 16 sections by its top 4 bits
t = y_7 y_6 y_5 y_4; each section's 17 digit values are replaced by one P = +-(A + B) X with
A, B powers of two (PPA, PPB). The magnitudes are symmetric in the one's complement
u = (y_6 y_5 y_4) xor y_7 and the sign is c = y_7, so the encoders reduce to three shared XORs
(Table III; the printed eqs. (6)-(7) lost overbars in places, e.g. A_32M as printed is also 1
for t = 0100, so the encoders are written from Table III). For an AR digit of d bits
(radix-2^d, d >= 5) the same table is used with every multiple scaled by 2^(d-8).
"""
import numpy as np

# u -> (A, B) in units of X (Table III, t = 0000..0111; t = 1xxx is the negation of u = ~xxx)
MAG = ((0, 8), (16, 8), (32, 8), (32, 16), (64, 8), (64, 16), (64, 32), (64, 64))


def shift(mult, d):
    """Column shift of the multiple `mult` X for an AR digit of d bits."""
    return mult.bit_length() - 1 + d - 8


def section(t):
    """(A, B, negative) for the 4-bit pattern t."""
    neg = t >= 8
    return MAG[(t & 7) ^ (7 if neg else 0)] + (neg,)


def digit(lo, d, zero_fix=False):
    """Approximate digit value P / X for the signed d-bit values lo (numpy array)."""
    lo = np.asarray(lo, np.int64)
    t = (lo >> (d - 4)) & 15
    val = np.array([(a + b) * (-1 if neg else 1) for a, b, neg in map(section, range(16))],
                   np.int64)
    p = (val[t] << d) >> 8                           # (A + B) is a multiple of 8, d >= 5
    return np.where(lo == 0, 0, p) if zero_fix else p


def encoder(net, y, low=None):
    """Select signals ({16, 32, 64: A_xM}, {8, 16, 32, 64: B_xM}) from y = [y4, y5, y6, y7];
    `low` (all d bits of the digit) gates B_8M with their OR (zero fix, not in the paper)."""
    u0, u1, u2 = (net.XOR(y[k], y[3]) for k in range(3))
    nu1, nu2 = net.NOT(u1), net.NOT(u2)
    sel_a = {16: net.AND(nu2, net.AND(nu1, u0)), 32: net.AND(nu2, u1), 64: u2}
    maj = net.OR(net.AND(u2, u1), net.AND(u0, net.OR(u2, u1)))
    b8 = net.NOT(maj)
    if low is not None:
        b8 = net.AND(b8, net.any(low))
    sel_b = {8: b8, 16: net.AND(u0, net.XOR(u1, u2)),
             32: net.AND(net.AND(u2, u1), net.NOT(u0)), 64: net.AND(net.AND(u2, u1), u0)}
    name = lambda s, tag: {m: net.name(x, f'{tag}_{m}m') for m, x in s.items()}
    return name(sel_a, 'enc_a'), name(sel_b, 'enc_b')
