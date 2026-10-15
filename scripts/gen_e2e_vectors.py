#!/usr/bin/env python3
"""Test vectors for the dla_e2e_chip unit testbenches (tb/e2e_requant_tb.sv).

Bit-true Python reference of the G300 integer epilogue (same arithmetic as
g300_pipeline_top S_REQ and the e2e spec golden_model.py).  Writes
<outdir>/e2e_requant_vectors.memh, one 112-bit hex word per vector:

    [104]     mode (1 = tanh, 0 = ReLU)
    [103:80]  acc   (24 b two's complement)
    [79:72]   bias  (8 b)
    [71:40]   M_a   (32 b unsigned)
    [39:8]    M_b   (32 b unsigned)
    [7:0]     expected q (ReLU: 0..127, tanh: pixel int8)

Vector set: the 1,296 golden (acc, bias, M) tuples of the reference image
(256 L0 + 256 L2 + 784 L4 neurons), corner cases, and --random N random tuples.

Usage (repo root): python3 scripts/gen_e2e_vectors.py <outdir> [--random 40000] [--seed 1]
"""
import argparse
import random
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
WD = REPO / 'weights_vh/mnist_gan_mlp'
S = 16
TM = 4 << 20
GOLD_M = dict(MA0=1173, MB0=93743, MA2=1102, MB2=35580, MW4=32731085, MB4=437099189)


def rd(p, b):
    o = []
    for t in Path(p).read_text().split():
        v = int(t, 16)
        o.append(v - (1 << b) if (v >> (b - 1)) & 1 else v)
    return o


LUT = rd(REPO / 'tb/data/g300_fp/g300_tanh_lut_fp.memh', 24)


def relu_rq(a, b, ma, mb):
    t = a * ma + b * mb
    if t < 0:
        return 0
    return min((t + (1 << (S - 1))) >> S, 127)


def tanh_rq(a, b, mw, mb):
    pre = (a * mw + b * mb + (1 << (S - 1))) >> S
    pre = max(-TM, min(TM, pre))
    idx = (pre + TM) >> 8
    p = (((LUT[idx] + (1 << 20)) * 255) + (1 << 20)) >> 21
    return max(0, min(255, p)) - 128


def ref(mode, a, b, ma, mb):
    return tanh_rq(a, b, ma, mb) if mode else relu_rq(a, b, ma, mb)


def mv(W, x, o, i):
    return [sum(W[r * i + k] * x[k] for k in range(i)) for r in range(o)]


def golden_tuples():
    W0, b0, W2, b2, W4, b4 = [rd(WD / f'G300_{n}.memh', 8) for n in
                              ('0_weight', '0_bias', '2_weight', '2_bias', '4_weight', '4_bias')]
    zq = rd(REPO / 'tb/data/g300_int8/g300_zq.memh', 8)
    m = GOLD_M
    a0 = mv(W0, zq, 256, 64)
    h0 = [relu_rq(a0[i], b0[i], m['MA0'], m['MB0']) for i in range(256)]
    a2 = mv(W2, h0, 256, 256)
    h2 = [relu_rq(a2[i], b2[i], m['MA2'], m['MB2']) for i in range(256)]
    a4 = mv(W4, h2, 784, 256)
    v = [(0, a0[i], b0[i], m['MA0'], m['MB0']) for i in range(256)]
    v += [(0, a2[i], b2[i], m['MA2'], m['MB2']) for i in range(256)]
    v += [(1, a4[i], b4[i], m['MW4'], m['MB4']) for i in range(784)]
    gold = rd(REPO / 'tb/data/g300_int8/g300_int8_rtl.memh', 8)
    assert [ref(*t) for t in v[512:]] == gold, 'golden model mismatch'
    return v


def corners():
    A = [0, 1, -1, (1 << 23) - 1, -(1 << 23), 24742, -24742, 12345, -77]
    B = [0, 1, -1, 127, -128]
    M = [0, 1, (1 << 32) - 1, (1 << 31), 1173, 93743, 32731085, 437099189]
    v = []
    for mode in (0, 1):
        for a in A:
            for b in B:
                for ma in M:
                    for mb in (M[0], M[2], M[5], M[7]):
                        v.append((mode, a, b, ma, mb))
    # t right at the ReLU / rounding boundaries: acc*1 + 0 with M_a = 1
    for t in (-1, 0, 1, (1 << 15) - 1, 1 << 15, (1 << 15) + 1,
              (127 << 16) - (1 << 15) - 1, (127 << 16) - (1 << 15), (127 << 16) + (1 << 15),
              (128 << 16) - (1 << 15) - 1, (128 << 16) - (1 << 15)):
        v.append((0, t, 0, 1, 0))
    # tanh clamp boundary: pre = +/-2^22 +/- 1  (acc*2^16 with M_a = 2^16 -> pre = acc)
    for p in (TM - 1, TM, TM + 1, -TM - 1, -TM, -TM + 1, 0, 255, 256, -256, -257):
        v.append((1, p, 0, 1 << 16, 0))
    return v


def randoms(n, rng):
    v = []
    for _ in range(n):
        mode = rng.randrange(2)
        kind = rng.randrange(4)
        if kind == 0:      # fully random
            a = rng.randrange(-(1 << 23), 1 << 23)
            ma = rng.randrange(1 << 32)
            mb = rng.randrange(1 << 32)
        elif kind == 1:    # realistic G300-like magnitudes, around the active range
            a = rng.randrange(-30000, 30000)
            ma = rng.choice([1173, 1102, 32731085]) + rng.randrange(-64, 64)
            mb = rng.choice([93743, 35580, 437099189]) + rng.randrange(-64, 64)
        elif kind == 2:    # pre near the interesting region for both modes
            a = rng.randrange(-(1 << 12), 1 << 12)
            ma = rng.randrange(1 << 22) if mode else rng.randrange(1 << 13)
            mb = rng.randrange(1 << 24) if mode else rng.randrange(1 << 15)
        else:              # small M, large acc
            a = rng.randrange(-(1 << 23), 1 << 23)
            ma = rng.randrange(1 << 12)
            mb = rng.randrange(1 << 20)
        b = rng.randrange(-128, 128)
        v.append((mode, a, b, ma, mb))
    return v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('outdir')
    ap.add_argument('--random', type=int, default=40000)
    ap.add_argument('--seed', type=int, default=1)
    a = ap.parse_args()
    rng = random.Random(a.seed)
    vec = golden_tuples() + corners() + randoms(a.random, rng)
    out = Path(a.outdir)
    out.mkdir(parents=True, exist_ok=True)
    lines = []
    for mode, acc, b, ma, mb in vec:
        q = ref(mode, acc, b, ma, mb) & 0xFF
        w = (mode << 104) | ((acc & 0xFFFFFF) << 80) | ((b & 0xFF) << 72) | (ma << 40) | (mb << 8) | q
        lines.append(f'{w:028x}')
    (out / 'e2e_requant_vectors.memh').write_text('\n'.join(lines) + '\n')
    print(f'{len(vec)} vectors -> {out / "e2e_requant_vectors.memh"}')


if __name__ == '__main__':
    main()
