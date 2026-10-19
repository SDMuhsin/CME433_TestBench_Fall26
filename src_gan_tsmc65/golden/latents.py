"""Benchmark latents: z ~ N(0, I_64) from torch.randn(n, 64, seed), quantised with the model's
static input scale sZ (zq = clamp(round(z / sZ), -127, 127)), written as n*64 int8 memh lines.
The draw is a prefix of any longer one with the same seed: the first 256 of --n 10000 are the
committed model/fmnist/latents.memh (bench/run_bench.sh --n N > 256 builds the longer set).

Width 16 (--width 16): the INT16 model's sZ, clamp +/-32767, 16-bit memh (model/fmnist_w16).

python3 -m src_gan_tsmc65.golden.latents [--width 8] [--n 256] [--seed 2000] [--out <model>/latents.memh]
"""
import argparse
import json

import numpy as np

from ..common.memh import write_memh
from ..common.paths import model_dir


def quant_z(z, sz, width=8):
    q = (1 << (width - 1)) - 1
    return np.clip(np.round(z / sz), -q, q).astype(np.int64)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--n', type=int, default=256)
    ap.add_argument('--seed', type=int, default=2000)
    ap.add_argument('--width', type=int, default=8)
    ap.add_argument('--out')
    a = ap.parse_args()
    mdir = model_dir(a.width)
    import torch
    z = torch.randn(a.n, 64, generator=torch.Generator().manual_seed(a.seed)).double().numpy()
    sz = json.loads((mdir / 'quant.json').read_text())['calibration']['sZ']
    out = a.out or str(mdir / 'latents.memh')
    write_memh(out, quant_z(z, sz, a.width), bits=a.width)
    print(f'{a.n} latents (seed {a.seed}, sZ {sz:.6g}, {a.width}-bit) -> {out}')


if __name__ == '__main__':
    main()
