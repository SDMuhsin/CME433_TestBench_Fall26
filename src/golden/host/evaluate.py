"""Golden-arithmetic bits-per-byte on the same fixed crops as src.model.evaluate."""
import argparse

import numpy as np

from src.model.data import eval_segments, load_bin

from ..arith.fp import value
from ..net.model import HwModel
from ..data.weights import load_params


def bits_per_byte(cfg, P, segs):
    """Run all crops in parallel token by token (state reset per crop); host log-softmax in float64."""
    model = HwModel(cfg, P, batch=len(segs))
    total = 0.0
    for t in range(segs.shape[1] - 1):
        z = value(model.step(segs[:, t])).astype(np.float64)
        m = z.max(-1, keepdims=True)
        lse = m[:, 0] + np.log(np.exp(z - m).sum(-1))
        total += np.sum(lse - z[np.arange(len(segs)), segs[:, t + 1]])
    return total / (len(segs) * (segs.shape[1] - 1)) / np.log(2)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('params')
    ap.add_argument('val_bin')
    ap.add_argument('--n', type=int, default=256)
    ap.add_argument('--length', type=int, default=1024)
    a = ap.parse_args()
    cfg, P = load_params(a.params)
    segs = eval_segments(load_bin(a.val_bin), a.n, a.length)
    print(f'golden bpb {bits_per_byte(cfg, P, segs):.4f}')


if __name__ == '__main__':
    main()
