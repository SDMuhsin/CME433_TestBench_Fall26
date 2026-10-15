"""Golden-arithmetic bits per byte on the same fixed crops as src_int8.model.evaluate.

python3 -m src_int8.golden.host.evaluate <params.npz> <val.bin> [--n 256 --length 1024]
"""
import argparse
import time

import numpy as np

from ...model.data import eval_segments, load_bin
from ..io.params import load_params
from ..model import HwModel
from .sampler import logits_to_float


def nll(z, target):
    """Host log-softmax in float64: z [b, V] -> -log p(target) [b] (nats)."""
    m = z.max(-1, keepdims=True)
    return m[:, 0] + np.log(np.exp(z - m).sum(-1)) - z[np.arange(len(z)), target]


def bits_per_byte(cfg, P, segs, log_every=0):
    """All crops in parallel, token by token, state reset per crop; host log-softmax in float64."""
    model = HwModel(cfg, P, batch=len(segs))
    total, t0 = 0.0, time.time()
    for t in range(segs.shape[1] - 1):
        total += nll(logits_to_float(model.step(segs[:, t])), segs[:, t + 1]).sum()
        if log_every and (t + 1) % log_every == 0:
            print(f'  {t + 1} tokens, {time.time() - t0:.0f} s', flush=True)
    return total / (len(segs) * (segs.shape[1] - 1)) / np.log(2)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('params')
    ap.add_argument('val_bin')
    ap.add_argument('--n', type=int, default=256)
    ap.add_argument('--length', type=int, default=1024)
    ap.add_argument('--log-every', type=int, default=0)
    a = ap.parse_args()
    cfg, P = load_params(a.params)
    segs = eval_segments(load_bin(a.val_bin), a.n, a.length)
    print(f'golden bpb {bits_per_byte(cfg, P, segs, a.log_every):.4f}')


if __name__ == '__main__':
    main()
