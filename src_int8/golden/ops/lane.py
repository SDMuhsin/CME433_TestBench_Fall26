"""Spec section 4: the MAC lane and the writeback, as pure int64 numpy.

  mac(base, a, b, ps) = base + rsh(a * b, ps)          a: signed 24 b, b: signed 16 b, |acc| < 2^31
  wb_sh(acc, sh)      = rsh(acc, sh)
  wb_rq(acc, M, s)    = (acc * M + 2^(s-1)) >> s        RQ pair (M, s) per row
  sh / rq             = sat_w(wb_x(acc) + addend)       w in {8, 16, 24}, 32 = raw

`dot` is the batched exact integer GEMV (sum of `rsh(w * x, ps)` over k); integer sums are
order independent, so a matmul equals the lane's sequential accumulation.  The accumulator
bound is asserted from the operand ranges (K * max|a| * max|b| >> ps < 2^31), which covers
every partial sum in any order.
"""
import numpy as np

from .formats import M_HI, M_LO, S_HI, S_LO, fits, rsh, sat

I64 = np.int64
ACC_LIM = 1 << 31


def _i64(v):
    return np.asarray(v, dtype=I64)


def mac(base, a, b, ps=0):
    """One lane step on broadcastable arrays."""
    a, b = _i64(a), _i64(b)
    assert fits(a, 24) and fits(b, 16), 'lane operand out of range'
    acc = _i64(base) + rsh(a * b, ps)
    assert fits(acc, 32), 'accumulator overflow'
    return acc


def dot(W, x, ps=0, init=0):
    """acc[..., o] = init + sum_k rsh(W[o, k] * x[..., k], ps); W [O, K], x [..., K]."""
    W, x = _i64(W), _i64(x)
    assert fits(W, 24) and fits(x, 16), 'lane operand out of range'
    K = W.shape[-1]
    bound = K * int(np.abs(W).max(initial=0)) * int(np.abs(x).max(initial=0))
    assert (bound >> ps) + abs(int(np.max(np.abs(_i64(init))))) < ACC_LIM, 'accumulator bound'
    if ps == 0:
        acc = x @ W.T
    else:
        acc = rsh(x[..., None, :] * W, ps).sum(-1)
    return _i64(init) + acc


def wb_sh(acc, sh):
    assert 0 <= sh <= 31
    return rsh(acc, sh)


def wb_rq(acc, rq):
    """rq: int array [..., 2] of (M, s), broadcast against acc's last axis."""
    rq = _i64(rq)
    M, s = rq[..., 0], rq[..., 1]
    assert np.all((M >= M_LO) & (M < M_HI)) and np.all((s >= S_LO) & (s <= S_HI)), 'RQ range'
    prod = _i64(acc) * M                                  # exact, 48 bits
    return (prod + (I64(1) << (s - 1))) >> s


def sh(acc, k, w, addend=0):
    """sat_w(wb_sh(acc, k) + addend)."""
    return sat(wb_sh(acc, k) + _i64(addend), w)


def rq(acc, pair, w, addend=0):
    """sat_w(wb_rq(acc, RQ) + addend)."""
    return sat(wb_rq(acc, pair) + _i64(addend), w)
