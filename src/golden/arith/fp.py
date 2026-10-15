"""FP16 storage + FP32 MAC-lane arithmetic (bit-exact contract, spec section 3).

All values are carried as uint16 FP16 bit patterns. Inputs are canonical: no subnormals
(FTZ to +0), no Inf/NaN (saturated to +-65504), never -0. The MAC lane computes
acc = RNE32(acc + a*b) with the FP16xFP16 product exact in FP32, and writes back with
`writeback` (optional exact 2^s scale, FTZ below 2^-14, RNE to FP16, saturate).
"""
import numpy as np

F16, F32, U16 = np.float16, np.float32, np.uint16
FP16_MAX = 0x7BFF
MIN_NORMAL = 2.0 ** -14


def canon16(bits):
    """Canonicalise FP16 bit patterns: subnormal/-0 -> +0, Inf/NaN -> +-65504."""
    b = np.array(bits, dtype=U16)
    e = (b >> 10) & 31
    b[e == 0] = 0
    sat = e == 31
    b[sat] = (b[sat] & 0x8000) | FP16_MAX
    return b


def to_fp16(x):
    """Host-side export float -> canonical FP16 bits (RNE, FTZ, saturate)."""
    return writeback(np.asarray(x, dtype=np.float64))


def value(bits):
    """FP16 bits -> exact FP32 values."""
    return np.asarray(bits, dtype=U16).view(F16).astype(F32)


def writeback(acc, scale=0):
    """Lane output: v = acc * 2^scale (exact), |v| < 2^-14 -> +0, else RNE to FP16, saturate."""
    v = np.ldexp(np.asarray(acc, dtype=np.float64), scale)
    with np.errstate(over='ignore'):
        h = v.astype(F16)                       # numpy float64 -> float16 is a single RNE
    b = np.array(h.view(U16), dtype=U16)
    inf = np.isinf(h)
    b[inf] = (b[inf] & 0x8000) | FP16_MAX
    b[np.abs(v) < MIN_NORMAL] = 0
    return b


def mac(acc, a_bits, b_bits):
    """One lane step: acc + a*b, product exact in FP32, one FP32 RNE (no FMA)."""
    return (np.asarray(acc, dtype=F32) + value(a_bits) * value(b_bits)).astype(F32)


def dot(pairs, init=None):
    """FP32 accumulation of init (FP16 bits or +0) followed by the pairs in list order."""
    a0, b0 = pairs[0]
    shape = np.broadcast_shapes(np.shape(a0), np.shape(b0))
    acc = np.zeros(shape, F32) if init is None else np.broadcast_to(value(init), shape).astype(F32)
    for a, b in pairs:
        acc = mac(acc, a, b)
    return acc


def mul(a_bits, b_bits):
    """Elementwise product rounded once to FP16."""
    return writeback(dot([(a_bits, b_bits)]))


def gemv(W, x, init=None):
    """y[..., o] = FP16(init[o] + sum_k W[o, k] * x[..., k]), k ascending.

    W: [O, K] bits; x: [..., K] bits; init: [O] or [..., O] bits or None.
    """
    acc = np.zeros(np.shape(x)[:-1] + (W.shape[0],), F32)
    if init is not None:
        acc = acc + value(init)
    for k in range(W.shape[1]):
        acc = mac(acc, W[:, k], x[..., k:k + 1])
    return writeback(acc)
