#!/usr/bin/env python3
"""Build dla_fp16_chip test data (host stream + bit-exact expected outputs) from a float checkpoint.

For each seed s: z = torch.randn(1, 64, generator=manual_seed(s)) (float64), converted to FP16 (RNE, FTZ).
Weights/biases: float32 checkpoint -> FP16 (RNE, FTZ, saturate).  Golden arithmetic: scripts/fp16_golden.py.

Outputs, per seed, in <out>/seed_<s>/:
  stream.memh        567,968 bytes (one hex byte per line) = the STREAM_Q payload:
                     z[0..63], then L0/L2/L4, per output neuron r: b[r], W[r, 0..K-1];
                     every FP16 word MSB byte first
  expected_pix.memh  784 uint8 pixels (row-major 28x28)
  h0_fp16.memh, h2_fp16.memh  256 FP16 activations (hierarchical TB checks)
  z_fp16.memh, y4_fp16.memh, z.txt
usage: gen_fp16_stream.py --ckpt <G.ckpt> --out <dir> [--seeds 0-7]
"""
import argparse, sys
from pathlib import Path
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import fp16_golden as g


def seeds_arg(s):
    if '-' in s:
        a, b = s.split('-'); return list(range(int(a), int(b) + 1))
    return [int(x) for x in s.split(',')]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ckpt', default=str(g.MNIST_CKPT))
    ap.add_argument('--out', required=True)
    ap.add_argument('--seeds', type=seeds_arg, default=list(range(8)))
    a = ap.parse_args()
    import torch
    P, Q, st = g.load_params(a.ckpt)
    T = g.build_tanh_rom()
    out = Path(a.out); out.mkdir(parents=True, exist_ok=True)
    for s in a.seeds:
        z = torch.randn(1, 64, generator=torch.Generator().manual_seed(s)).double().numpy()[0]
        zb = g.to_fp16_bits(z)
        R = g.run(Q, zb, T)
        words = g.stream_words(Q, zb)
        by = np.empty(2 * len(words), dtype=np.uint8)
        by[0::2] = words >> 8; by[1::2] = words & 0xFF          # MSB byte first
        assert len(by) == 567968
        d = out / f'seed_{s}'; d.mkdir(exist_ok=True)
        (d / 'stream.memh').write_text(''.join(f'{int(b):02x}\n' for b in by))
        (d / 'expected_pix.memh').write_text(''.join(f'{int(p):02x}\n' for p in R['pix']))
        for n in ('h0', 'h2', 'y4'): g.wr16(d / f'{n}_fp16.memh', R[n])
        g.wr16(d / 'z_fp16.memh', zb)
        np.savetxt(d / 'z.txt', z, fmt='%.9f')
        f = g.float_forward(P, z)
        print(f'seed {s}: stream {len(by)} B, MAD vs float {np.abs(R["pix"] - f).mean():.4f}/255 -> {d}')


if __name__ == '__main__':
    main()
