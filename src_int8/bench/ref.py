"""Python bit-exact reference (golden HwModel) on the benchmark crops: logits + per-position NLL.

python3 -m src_int8.bench.ref <bench_dir>      -> <bench_dir>/ref/{logits.npy, nll.npy}
All crops run as one batch with the state reset per crop, as golden.host.evaluate does.
"""
import argparse
import time
from pathlib import Path

import numpy as np

from ..golden.io.params import load_params
from ..golden.model import HwModel
from .common import PARAMS, nll_bits


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('bench', type=Path)
    a = ap.parse_args()
    segs = np.load(a.bench / 'crops.npy')
    n, L = segs.shape[0], segs.shape[1] - 1
    cfg, P = load_params(PARAMS)
    model, t0 = HwModel(cfg, P, batch=n), time.time()
    logits = np.empty((n, L, cfg['vocab']), np.int16)
    for t in range(L):
        logits[:, t] = model.step(segs[:, t])
    out = a.bench / 'ref'
    out.mkdir(exist_ok=True)
    np.save(out / 'logits.npy', logits)
    np.save(out / 'nll.npy', np.stack([nll_bits(logits[i], segs[i]) for i in range(n)]))
    print(f'golden reference: {n} x {L} tokens in {time.time() - t0:.0f} s -> {out}')


if __name__ == '__main__':
    main()
