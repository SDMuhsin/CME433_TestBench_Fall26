"""Golden vs float next-byte loss over long contexts with the state carried (no reset).

Crops of `--length` contiguous validation bytes (stories joined by EOS, so the state runs across
story boundaries).  Three models on the same crops:
  golden   bit-exact integer model (INT24 state, LUTs, recurrence rounding)
  fakeq    the QAT torch model (fake quant, chunked scan without recurrence rounding), optional
  float    float64 exact recurrence of the same checkpoint
Saves per-position NLL, per-step state statistics (max |h|, saturated INT24 entries, dA == 1
fraction, relative state error) for `report.py`.

python3 -m src_int8.longctx.long_eval params.npz qat.pt val.bin out.npz [--n 256 --length 8192]
"""
import argparse
import time

import numpy as np

from ..golden.host.evaluate import nll
from ..golden.host.sampler import logits_to_float
from ..golden.io.params import load_params
from ..golden.model import HwModel
from ..golden.ops.formats import ACT
from ..model.data import eval_segments, load_bin
from .float_ref import FloatModel, load

H_SCALE = ACT['H'].scale
H_LIM = ACT['H'].hi
P_HIST_BITS = 10        # p histogram resolution 2^-10 (resolves tau up to ~1,500 tokens)


def state_stats(gm, fm, probes):
    """Per layer: golden max|h|, float max|h|, #saturated INT24 h, frozen (dA == 32767) fraction, rel err."""
    out = []
    for l, (hg_i, hf) in enumerate(zip(gm.h, fm.h)):
        hg = hg_i * H_SCALE
        frozen = np.mean(probes[l]['dA'] >= 32767)
        err = np.linalg.norm(hg - hf) / max(np.linalg.norm(hf), 1e-30)
        sat = int(np.sum((hg_i >= H_LIM) | (hg_i <= -H_LIM - 1)))
        out.append((np.abs(hg).max(), np.abs(hf).max(), sat, frozen, err))
    return np.array(out)


def fakeq_nll(ckpt, segs, device, chunk=16):
    """Per-position NLL of the QAT fake-quant torch model over whole crops (state carried)."""
    import torch
    import torch.nn.functional as F
    from ..model.qat.qmamba import q_forward
    from ..model.train.common import load_checkpoint
    m = load_checkpoint(ckpt, device)
    out = np.zeros((segs.shape[0], segs.shape[1] - 1), np.float32)
    with torch.no_grad():
        for i in range(0, len(segs), chunk):
            s = torch.as_tensor(segs[i:i + chunk], device=device)
            z = q_forward(m, s[:, :-1]).float()
            out[i:i + chunk] = F.cross_entropy(z.transpose(1, 2), s[:, 1:], reduction='none').cpu().numpy()
    return out


def run(cfg, P, cfgf, Pf, segs, log_every=256):
    n, L = segs.shape[0], segs.shape[1] - 1
    gm, fm = HwModel(cfg, P, n), FloatModel(cfgf, Pf, n)
    nll_g, nll_f = np.zeros((n, L), np.float32), np.zeros((n, L), np.float32)
    stats = np.zeros((L, cfg['n_layer'], 5))
    p_hist = np.zeros((16 << P_HIST_BITS) + 2, np.int64)   # histogram of -p in 2^-P_HIST_BITS steps
    t0 = time.time()
    for t in range(L):
        probes = []
        zg = logits_to_float(gm.step(segs[:, t], probes))
        zf = fm.step(segs[:, t])
        nll_g[:, t], nll_f[:, t] = nll(zg, segs[:, t + 1]), nll(zf, segs[:, t + 1])
        stats[t] = state_stats(gm, fm, probes)
        for pr in probes:
            p_hist += np.bincount(np.minimum(-pr['p'].ravel() >> (19 - P_HIST_BITS), (16 << P_HIST_BITS) + 1),
                                  minlength=(16 << P_HIST_BITS) + 2)
        if (t + 1) % log_every == 0:
            k = slice(t + 1 - log_every, t + 1)
            print(f'{t + 1:6d}  golden {nll_g[:, k].mean() / np.log(2):.4f}  '
                  f'float {nll_f[:, k].mean() / np.log(2):.4f}  max|h| {stats[t, :, 0].max():.1f}  '
                  f'sat {int(stats[:t + 1, :, 2].sum())}  state err {stats[t, :, 4].max():.3f}  '
                  f'({time.time() - t0:.0f} s)', flush=True)
    return dict(nll_golden=nll_g, nll_float=nll_f, stats=stats, p_hist=p_hist, p_hist_bits=P_HIST_BITS, segs=segs)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('params', help='integer .npz (golden)')
    ap.add_argument('ckpt', help='QAT .pt checkpoint (float reference and fake-quant model)')
    ap.add_argument('val_bin')
    ap.add_argument('out', help='output .npz')
    ap.add_argument('--n', type=int, default=256)
    ap.add_argument('--length', type=int, default=8192)
    ap.add_argument('--seed', type=int, default=4321)
    ap.add_argument('--fakeq-device', default='', help="e.g. cuda:1: also run the QAT fake-quant model")
    a = ap.parse_args()
    cfg, P = load_params(a.params)
    cfgf, Pf = load(a.ckpt)
    segs = eval_segments(load_bin(a.val_bin), a.n, a.length, seed=a.seed)
    res = run(cfg, P, cfgf, Pf, segs)
    if a.fakeq_device:
        res['nll_fakeq'] = fakeq_nll(a.ckpt, segs, a.fakeq_device)
    np.savez_compressed(a.out, **res)


if __name__ == '__main__':
    main()
