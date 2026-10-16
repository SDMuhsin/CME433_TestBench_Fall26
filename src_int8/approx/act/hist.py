"""Joint histogram of the mq_mul8 operands (a = INT8 weight, b = INT8 activation) on benchmark
crops, from the bit-exact golden model (the products src_int8/bench/emu routes through mq_mul8).

python3 -m src_int8.approx.act.hist [--crops 4] [--tokens 128]  -> build/approx/act/hist.npy
"""
import argparse
from pathlib import Path

import numpy as np

from ...bench.common import PARAMS
from ...bench.emu import model as emu
from ...golden.io.params import load_params
from ...golden.model import HwModel

ROOT = Path(__file__).resolve().parents[3]
R = np.arange(-128, 128)


class _Counting:
    """product table that counts every lookup"""
    def __init__(self):
        self.t = R[:, None] * R[None, :]
        self.h = np.zeros((256, 256), np.int64)

    def __getitem__(self, idx):
        a, b = np.broadcast_arrays(*idx)
        np.add.at(self.h, (a.ravel(), b.ravel()), 1)
        return self.t[idx]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--crops', type=int, default=4)
    ap.add_argument('--tokens', type=int, default=128)
    ap.add_argument('--bench', type=Path, default=ROOT / 'build/bench/c512x1024')
    a = ap.parse_args()
    segs = np.load(a.bench / 'crops.npy')[:a.crops]
    cfg, P = load_params(PARAMS)
    model, tab = HwModel(cfg, P, batch=a.crops), _Counting()
    with emu.approx(np.zeros((256, 256), np.int64)):          # patch the layers ...
        dot = emu._dot(tab)                                   # ... then route through the counter
        for mod in (emu.proj, emu.scan, emu.conv):
            mod.dot = dot
        emu.block.in_x_conv = emu._in_x_conv(tab, dot)
        for t in range(a.tokens):
            model.step(segs[:, t])
    out = ROOT / 'build/approx/act'
    out.mkdir(parents=True, exist_ok=True)
    np.save(out / 'hist.npy', tab.h)
    n = tab.h.sum()
    pa, pb = tab.h.sum(1) / n, tab.h.sum(0) / n
    print(f'{n} products ({n // (a.crops * a.tokens)} per token) -> {out / "hist.npy"}')
    for nm, p in (('a (weight)', pa), ('b (activation)', pb)):
        print(f'  {nm:15s} mean {(R * p).sum():+.3f}  E|x| {(abs(R) * p).sum():.2f}  P(x=0) {p[128]:.4f}  '
              f'P(|x|<32) {p[96:160].sum():.3f}  P(x<0) {p[:128].sum():.3f}')


if __name__ == '__main__':
    main()
