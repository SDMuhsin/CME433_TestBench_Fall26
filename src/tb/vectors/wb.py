"""mb_fp32_wb vectors: "acc scale y", y = writeback(acc, scale) (FTZ, RNE, saturate, 2^s scale).

Every legal FP16 value as an exact acc; RNE ties of both parities; boundaries around 2^-14,
65504 and 65520; random FP32 normals whose scaled exponent straddles the FP16 range; zeros.
Scales cover the spec's uses (0, -6, rsqrt -7..7, exp2 clamp -128) and the full 8-bit range.
"""
import numpy as np

from src.golden.arith.fp import writeback

from .common import F32, U32, f32bits, legal16, rng, value, write_hex


def _boundaries():
    out = []
    for v in (2.0 ** -14, 65504.0, 65520.0):
        base = int(f32bits(F32(v)))
        out += [base + d for d in range(-64, 65)]
    b = np.array(out, dtype=np.int64)
    return np.concatenate([b, b | 0x80000000]).astype(U32)


def wb_vectors(path, n=300000):
    r = rng(2)
    ex = f32bits(value(legal16()))
    ties = ex[(ex & 0x7FFFFFFF) != 0][::2] | 0x1000                     # exactly half an ulp
    acc0 = np.concatenate([ex, ties, ties ^ 0x2000, _boundaries()]).astype(U32)
    s0 = np.zeros(len(acc0), dtype=np.int64)

    # random normals: scaled biased exponent e + s spread over 100 .. 150 (FTZ .. saturate)
    s1 = np.where(r.random(n) < 0.5, r.integers(-8, 9, n), r.integers(-128, 128, n))
    e1 = np.clip(r.integers(100, 151, n) - s1, 1, 254)
    acc1 = (r.integers(0, 1 << 23, n) | (e1 << 23) | (r.integers(0, 2, n) << 31)).astype(U32)

    # shifted copies of the exact / tie / boundary set, and zeros with any scale
    s2 = r.integers(-20, 21, len(acc0))
    e2 = ((acc0 >> 23) & 0xFF).astype(np.int64) - s2
    ok = (e2 >= 1) & (e2 <= 254)
    acc2 = ((acc0[ok] & 0x807FFFFF) | (e2[ok] << 23).astype(U32)).astype(U32)
    s3 = np.arange(-128, 128)
    acc3 = np.zeros(len(s3), dtype=U32)

    acc = np.concatenate([acc0, acc1, acc2, acc3]).astype(U32)
    sc = np.concatenate([s0, s1, s2[ok], s3])
    y = writeback(acc.view(F32), sc)
    return write_hex(path, [(acc, 8), (sc, 2), (y, 4)])


def generate(out):
    return {'fp32_wb': wb_vectors(out / 'fp32_wb.hex')}
