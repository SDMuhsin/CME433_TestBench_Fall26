"""Image sets scored by bench/real, all as uint8 [N, 28, 28] on the chip's 0..255 grey scale.

real      : Fashion-MNIST (torchvision, build/gan65/data), train 60k = the FID reference, test 10k
float     : the trained float generator (model/fmnist/G300_float.npz) on the unquantised latents
golden    : the bit-exact integer model of the chip (golden/model.py) on the quantised latents
            (INT8 model/fmnist, or INT16 model/fmnist_w16 for width 16)
rtl       : Verilator chip images of a run_bench.sh run (build/gan65/runs/<tag>_n<N>/rtl_u8.npy)
Latents: z = torch.randn(N, 64, seed 2000); the first 256 equal the committed model/fmnist/latents.memh.
"""
import json

import numpy as np

from ...common.paths import BUILD, MODEL, model_dir
from ...golden.latents import quant_z
from ...golden.model import forward, load_model
from ..images import to_u8

SEED = 2000


def real(train):
    from torchvision import datasets
    return datasets.FashionMNIST(str(BUILD / 'data'), train=train, download=True).data.numpy()


def latents(n):
    import torch
    return torch.randn(n, 64, generator=torch.Generator().manual_seed(SEED)).double().numpy()


def float_gen(n):
    """(tanh(G(z)) + 1) * 127.5, rounded: the float model on the chip's pixel scale."""
    with np.load(MODEL / 'G300_float.npz') as w:
        h = latents(n)
        for i in (0, 2):
            h = np.maximum(h @ w[f'{i}_weight'].T.astype(np.float64) + w[f'{i}_bias'], 0)
        y = np.tanh(h @ w['4_weight'].T.astype(np.float64) + w['4_bias'])
    return np.clip(np.round((y + 1) * 127.5), 0, 255).astype(np.uint8).reshape(-1, 28, 28)


def golden(n, width=8):
    mdir = model_dir(width)
    sz = json.loads((mdir / 'quant.json').read_text())['calibration']['sZ']
    return to_u8(forward(quant_z(latents(n), sz, width), load_model(mdir))['pix']).reshape(-1, 28, 28)


def rtl(tag, n):
    path = BUILD / 'runs' / f'{tag}_n{n}' / 'rtl_u8.npy'
    if not path.exists():
        raise SystemExit(f'missing {path}: run bench/run_bench.sh <variant> --n {n} first')
    u8 = np.load(path)
    if u8.shape != (n, 28, 28):
        raise SystemExit(f'{path}: shape {u8.shape}, expected ({n}, 28, 28)')
    return u8
