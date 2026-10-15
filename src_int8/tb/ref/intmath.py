"""Spec-formula integer primitives of mq_chip (spec.md sections 2 and 4), plain Python ints.

Team B's reference for the unit tests until src_int8/golden publishes its vectors.  Nothing here
is imported from src/ or src_int8/golden.
"""


def rsh(v, k):
    """Round half up, arithmetic shift: rsh(v, 0) = v, else (v + 2^(k-1)) >> k."""
    assert 0 <= k
    return v if k == 0 else (v + (1 << (k - 1))) >> k


def sat(v, w):
    """Clamp to the signed w-bit range (w = 32 passes raw)."""
    if w == 32:
        return v
    lo, hi = -(1 << (w - 1)), (1 << (w - 1)) - 1
    return lo if v < lo else hi if v > hi else v


def sext(v, w):
    """Interpret the low w bits of v as a signed integer."""
    v &= (1 << w) - 1
    return v - (1 << w) if v >> (w - 1) else v


def mac(base, a, b, ps):
    """One lane step: base + rsh(a * b, ps); asserts the INT32 accumulator bound."""
    assert -(1 << 23) <= a < (1 << 23) and -(1 << 15) <= b < (1 << 15), (a, b)
    acc = base + rsh(a * b, ps)
    assert -(1 << 31) <= acc < (1 << 31), f'accumulator overflow {acc}'
    return acc


def wb_sh(acc, sh):
    return rsh(acc, sh)


def wb_rq(acc, M, s):
    assert (1 << 14) <= M < (1 << 15) and 1 <= s <= 47, (M, s)
    return (acc * M + (1 << (s - 1))) >> s


def sh_w(acc, k, w, addend=0):
    return sat(wb_sh(acc, k) + addend, w)


def rq_w(acc, M, s, w, addend=0):
    return sat(wb_rq(acc, M, s) + addend, w)


def requant_pair(r):
    """Exact ratio r = s_w * s_in / s_out -> (M, s) per spec 3.3."""
    import math
    s = 14 - math.floor(math.log2(r))
    M = round(r * 2 ** s)
    if M == 1 << 15:
        M, s = 1 << 14, s - 1
    assert 1 <= s <= 47 and (1 << 14) <= M < (1 << 15)
    return M, s
