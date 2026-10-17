"""Benchmark latents: z ~ N(0, I_64) from torch.randn(n, 64, seed), quantised with the model's
static input scale sZ (zq = clamp(round(z / sZ), -127, 127)), written as n*64 int8 memh lines.

python3 -m src_gan_tsmc65.golden.latents [--n 256] [--seed 2000] [--out model/fmnist/latents.memh]
"""
import argparse
import json

import numpy as np

from ..common.memh import write_memh
from ..common.paths import MODEL


def quant_z(z, sz):
    return np.clip(np.round(z / sz), -127, 127).astype(np.int64)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--n', type=int, default=256)
    ap.add_argument('--seed', type=int, default=2000)
    ap.add_argument('--out', default=str(MODEL / 'latents.memh'))
    a = ap.parse_args()
    import torch
    z = torch.randn(a.n, 64, generator=torch.Generator().manual_seed(a.seed)).double().numpy()
    sz = json.loads((MODEL / 'quant.json').read_text())['calibration']['sZ']
    write_memh(a.out, quant_z(z, sz))
    print(f'{a.n} latents (seed {a.seed}, sZ {sz:.6g}) -> {a.out}')


if __name__ == '__main__':
    main()
