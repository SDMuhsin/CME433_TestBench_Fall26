#!/usr/bin/env python3
"""Unit-test vectors for the dla_fp16_chip FP units (golden = scripts/fp16_golden.py / numpy IEEE fp32).

<out>/fpu_vec.hex  : "a b acc sum"   fp16_mul + fp32_add_rne: sum = RNE32(acc + a*b) (canonical FTZ/sat inputs)
                     random codes (all exponents) + cancellations + large exponent gaps + RNE ties
<out>/epi_vec.hex  : "acc mode y pix" fp16_epi: y = fp16(acc) (FTZ/RNE/sat, ReLU if mode 0), pix (mode 1)
                     every legal FP16 value as an exact acc (tanh mode, exhaustive ROM check), FP16
                     rounding/overflow/FTZ boundaries, random accs
<out>/lane_vec.txt : fp16_lane neuron traces of one real image (MNIST seed 0, all 3 layers):
                     "B <bias>", "W <w> <x>" ..., "E <acc>"
usage: gen_fp16_unit_vectors.py <out_dir> [N_random]
"""
import sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import fp16_golden as g

out = Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
N = int(sys.argv[2]) if len(sys.argv) > 2 else 200000
rng = np.random.default_rng(2026)
F32, U16, U32 = np.float32, np.uint16, np.uint32


def f32bits(v): return np.asarray(v, dtype=F32).view(U32)


# ------------------------------------------------------------------ fpu
a = rng.integers(0, 65536, N, dtype=np.uint32).astype(U16)
b = rng.integers(0, 65536, N, dtype=np.uint32).astype(U16)
af, bf = g.b16(g.canon16(a)), g.b16(g.canon16(b))
p = (af * bf).astype(F32)
acc = (p * rng.choice([-1, 1], N) * rng.uniform(0.5, 2, N)).astype(F32)
k = rng.random(N) < 0.2; acc[k] = -p[k]                                     # exact cancellation
k = rng.random(N) < 0.2; acc[k] = (p[k] * F32(2.0) ** rng.integers(-30, 30, k.sum())).astype(F32)
k = rng.random(N) < 0.05; acc[k] = 0
k = rng.random(N) < 0.1; acc[k] = (-p[k] * (1 + rng.integers(-3, 4, k.sum()) * 2.0 ** -23)).astype(F32)
k = rng.random(N) < 0.1                                                     # RNE ties: acc 24/25 binades above p
acc[k] = (np.sign(rng.standard_normal(k.sum())) * np.abs(p[k]) * F32(2.0) ** rng.integers(21, 26, k.sum())
          * (1 + rng.integers(0, 2 ** 22, k.sum()) * 2.0 ** -23)).astype(F32)
a_ = np.abs(acc); acc[(a_ < 2 ** -126) | ~np.isfinite(acc)] = 0
with np.errstate(all='ignore'):
    s = (acc + p).astype(F32) + F32(0)
ok = np.isfinite(s) & ~((s != 0) & (np.abs(s) < 2 ** -126))
with open(out / 'fpu_vec.hex', 'w') as f:
    for i in np.nonzero(ok)[0]:
        f.write('%04x %04x %08x %08x\n' % (a[i], b[i], f32bits(acc[i]), f32bits(s[i])))

# ------------------------------------------------------------------ epilogue
T = g.build_tanh_rom()
allb = np.arange(65536, dtype=np.uint32).astype(U16)
legal = (g.canon16(allb) == allb) & (allb != 0x8000)
ex = g.b16(allb[legal])                                            # exact accs, every legal FP16
r16 = rng.integers(0, 1 << 32, N, dtype=np.uint64).astype(U32)     # random fp32 bit patterns ...
r16 = (r16 & 0x807FFFFF) | (rng.integers(95, 160, N).astype(U32) << 23)   # ... exp 2^-32 .. 2^32
bnd = []
for v in (2.0 ** -14, 65504.0, 65520.0, 65519.99):
    base = int(f32bits(F32(v)))
    bnd += [base + d for d in range(-40, 41)]
bnd = np.concatenate([np.array(bnd, dtype=np.int64).astype(U32), np.array(bnd, dtype=np.int64).astype(U32) | 0x80000000])
ties = (f32bits(ex[np.abs(ex) > 0][:20000]) | 0x1000).astype(U32)  # exactly half an FP16 ulp above
ties2 = (ties ^ 0x2000).astype(U32)                                # same tie, other LSB parity
accs = np.concatenate([f32bits(ex), r16, bnd, ties, ties2, np.array([0], dtype=U32)]).astype(U32)
accs = accs[(accs & 0x7F800000) != 0x7F800000]
accs = accs[~(((accs & 0x7F800000) == 0) & ((accs & 0x7FFFFF) != 0))]      # no fp32 subnormals (never occur)
accs = accs[accs != 0x80000000]
y = g.f32_to_f16(accs.view(F32))
yr = np.where(y & 0x8000, 0, y).astype(U16)
pix = g.tanh_pix(y, T)
with open(out / 'epi_vec.hex', 'w') as f:
    for i in range(len(accs)):
        f.write('%08x 0 %04x 00\n' % (accs[i], yr[i]))
        f.write('%08x 1 %04x %02x\n' % (accs[i], y[i], pix[i]))

# ------------------------------------------------------------------ lane traces
P, Q, _ = g.load_params(g.MNIST_CKPT)
import torch
z = torch.randn(1, 64, generator=torch.Generator().manual_seed(0)).double().numpy()[0]
zb = g.to_fp16_bits(z)
R = g.run(Q, zb, T)
with open(out / 'lane_vec.txt', 'w') as f:
    for Wn, bn, xb, an in (('W0', 'b0', zb, 'a0'), ('W2', 'b2', R['h0'], 'a2'), ('W4', 'b4', R['h2'], 'a4')):
        for r in range(Q[Wn].shape[0]):
            f.write('B %04x\n' % Q[bn][r])
            for kk in range(Q[Wn].shape[1]):
                f.write('W %04x %04x\n' % (Q[Wn][r, kk], xb[kk]))
            f.write('E %08x\n' % f32bits(R[an][r]))
print('vectors:', sum(1 for _ in open(out / 'fpu_vec.hex')), 'fpu,', 2 * len(accs), 'epi, 1296 lane neurons ->', out)
