"""Golden vs float64 next-byte loss over long contexts with the state carried (no reset).

Crops of `--length` contiguous bytes of the validation corpus (stories joined by EOS, so the
state runs across story boundaries). Saves per-position NLL for both models, per-step state
statistics and the histogram of decay exponents p seen by the golden scan. `report.py` turns
the .npz into the bucket table.
"""
import argparse
import time

import numpy as np

from src.golden.arith.fp import FP16_MAX, value
from src.golden.data.weights import load_params
from src.model.data import eval_segments, load_bin

from .float_ref import FloatModel, load_float_params
from .probe import ProbedHwModel, decay_of


def nll(z, target):
    """Host log-softmax in float64: z [b, V] -> -log p(target) [b] (nats)."""
    m = z.max(-1, keepdims=True)
    return m[:, 0] + np.log(np.exp(z - m).sum(-1)) - z[np.arange(len(z)), target]


def state_stats(gm, fm):
    """Per layer: golden max|h|, #saturated h, frozen (dA == 1) fraction, rel. state error."""
    out = []
    for l, (hg_bits, hf) in enumerate(zip(gm.h, fm.h)):
        hg = value(hg_bits).astype(np.float64)
        frozen = np.mean(value(decay_of(gm.p[l])) >= 1.0)
        err = np.linalg.norm(hg - hf) / max(np.linalg.norm(hf), 1e-30)
        sat = int(np.sum((hg_bits & 0x7FFF) == FP16_MAX))
        out.append((np.abs(hg).max(), np.abs(hf).max(), sat, frozen, err))
    return np.array(out)


def run(cfg16, P16, cfgf, Pf, segs, decay='hw', log_every=256):
    n, L = segs.shape[0], segs.shape[1] - 1
    gm, fm = ProbedHwModel(cfg16, P16, n, decay), FloatModel(cfgf, Pf, n)
    nll_g, nll_f = np.zeros((n, L), np.float32), np.zeros((n, L), np.float32)
    stats = np.zeros((L, cfg16['n_layer'], 5))
    p_counts = np.zeros(65536, np.int64)
    t0 = time.time()
    for t in range(L):
        zg = value(gm.step(segs[:, t])).astype(np.float64)
        zf = fm.step(segs[:, t])
        nll_g[:, t], nll_f[:, t] = nll(zg, segs[:, t + 1]), nll(zf, segs[:, t + 1])
        stats[t] = state_stats(gm, fm)
        for p in gm.p:
            p_counts += np.bincount(p.ravel(), minlength=65536)
        if (t + 1) % log_every == 0:
            k = slice(t + 1 - log_every, t + 1)
            print(f'{t + 1:6d}  golden {nll_g[:, k].mean() / np.log(2):.4f}  '
                  f'float {nll_f[:, k].mean() / np.log(2):.4f}  max|h| {stats[t, :, 0].max():.1f}  '
                  f'state err {stats[t, :, 4].max():.3f}  ({time.time() - t0:.0f} s)', flush=True)
    return dict(nll_golden=nll_g, nll_float=nll_f, stats=stats, p_counts=p_counts, segs=segs)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('params', help='FP16 .npz (golden)')
    ap.add_argument('ckpt', help='float .pt checkpoint')
    ap.add_argument('val_bin')
    ap.add_argument('out', help='output .npz')
    ap.add_argument('--n', type=int, default=256)
    ap.add_argument('--length', type=int, default=8192)
    ap.add_argument('--seed', type=int, default=4321)
    ap.add_argument('--decay', choices=('hw', 'float'), default='hw',
                    help="'float': ablation with exact 2^p in the state update (not hardware)")
    a = ap.parse_args()
    cfg16, P16 = load_params(a.params)
    cfgf, Pf = load_float_params(a.ckpt)
    segs = eval_segments(load_bin(a.val_bin), a.n, a.length, seed=a.seed)
    np.savez_compressed(a.out, **run(cfg16, P16, cfgf, Pf, segs, a.decay))


if __name__ == '__main__':
    main()
