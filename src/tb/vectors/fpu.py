"""mb_fp16_mul + mb_fp32_add_rne vectors: "a b acc p sum", p = exact a*b, sum = RNE32(acc + p).

Random canonical codes (all exponents) and realistic values, against accumulators chosen to hit
exact / near cancellation, large exponent gaps, RNE ties and zeros.  Plus the to-FP32 table:
"h f" for all 65536 codes, f = FP32(canon16(h)) (exhaustive).
"""
import numpy as np

from src.golden.arith.fp import mac

from .common import F32, U32, canon16, f32bits, rand16, real16, rng, value, write_hex


def _accs(r, p):
    n = len(p)
    acc = (p * r.choice([-1, 1], n) * r.uniform(0.5, 2, n)).astype(F32)
    pick = [r.random(n) < t for t in (0.15, 0.15, 0.05, 0.1, 0.1)]
    acc[pick[0]] = -p[pick[0]]                                             # exact cancellation
    k = pick[1]
    acc[k] = (p[k] * F32(2.0) ** r.integers(-30, 31, k.sum())).astype(F32)  # exponent gaps
    acc[pick[2]] = 0
    k = pick[3]                                                            # near cancellation
    acc[k] = (-p[k] * (1 + r.integers(-3, 4, k.sum()) * 2.0 ** -23)).astype(F32)
    k = pick[4]                                                            # RNE ties
    acc[k] = (np.sign(r.standard_normal(k.sum())) * np.abs(p[k]) * F32(2.0) ** r.integers(21, 26, k.sum())
              * (1 + r.integers(0, 2 ** 22, k.sum()) * 2.0 ** -23)).astype(F32)
    return acc


def mac_vectors(path, n=300000):
    r = rng(1)
    h = n // 2
    a = np.concatenate([rand16(r, h), real16(r, n - h)])
    b = np.concatenate([rand16(r, h), real16(r, n - h)])
    edge = np.array([0, 0x0400, 0x8400, 0x7BFF, 0xFBFF, 0x3C00, 0xBC00, 0x3BFF], dtype=a.dtype)
    ea, eb = np.meshgrid(edge, edge)
    a, b = np.concatenate([a, ea.ravel()]), np.concatenate([b, eb.ravel()])
    p = (value(a) * value(b)).astype(F32)
    p[p == 0] = 0                 # the lane's zero product is +0 (numpy may give -0)
    acc = _accs(r, p)
    acc[acc == 0] = 0             # the lane accumulator is never -0
    s = mac(acc, a, b)
    return write_hex(path, [(a, 4), (b, 4), (f32bits(acc), 8), (f32bits(p), 8), (f32bits(s), 8)])


def to_fp32_vectors(path):
    h = np.arange(65536, dtype=U32)
    f = value(canon16(h.astype(np.uint16)))
    return write_hex(path, [(h, 4), (f32bits(f), 8)])


def generate(out):
    return {'fpu_mac': mac_vectors(out / 'fpu_mac.hex'),
            'fp16_to_fp32': to_fp32_vectors(out / 'fp16_to_fp32.hex')}

