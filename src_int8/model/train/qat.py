"""Quantisation-aware fine-tuning from the FP16 checkpoint (spec section 9).

python3 -m src_int8.model.train.qat --ckpt e96.pt --train-bin train.bin --val-bin val.bin \
    --out mamba_e96_qat.pt [--steps 5000 --lr 3e-4 --warmup 200]

The checkpoint written has the float checkpoint's format plus a 'qat' entry with the recipe.
"""
import argparse
import json
import time

import numpy as np
import torch
import torch.nn.functional as F

from ..data import load_bin
from ..qat.qmamba import q_forward
from .common import batch_tensors, bpb, load_checkpoint, lr_at, quick_val, save_checkpoint


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--ckpt', required=True, help='float checkpoint to start from')
    ap.add_argument('--train-bin', required=True)
    ap.add_argument('--val-bin', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--steps', type=int, default=5000)
    ap.add_argument('--batch', type=int, default=64)
    ap.add_argument('--length', type=int, default=512)
    ap.add_argument('--lr', type=float, default=3e-4)
    ap.add_argument('--warmup', type=int, default=200)
    ap.add_argument('--device', default='cuda:1')
    ap.add_argument('--seed', type=int, default=0)
    ap.add_argument('--log-every', type=int, default=250)
    ap.add_argument('--no-compile', action='store_true')
    a = ap.parse_args()

    torch.manual_seed(a.seed)
    rng = np.random.default_rng(a.seed)
    model = load_checkpoint(a.ckpt, a.device).train()
    fwd = (lambda t: q_forward(model, t)) if a.no_compile else torch.compile(lambda t: q_forward(model, t))
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=0.01, betas=(0.9, 0.95))
    train, val = load_bin(a.train_bin), load_bin(a.val_bin)
    print(json.dumps({'config': model.cfg.to_dict(), 'args': vars(a)}), flush=True)
    print(f'step 0 qat val_bpb (no fine-tuning) {quick_val(fwd, val, a.length, a.device):.4f}',
          flush=True)
    t0 = time.time()
    for step in range(1, a.steps + 1):
        for g in opt.param_groups:
            g['lr'] = lr_at(step, a.steps, a.lr, a.warmup)
        x, y = batch_tensors(train, a.batch, a.length, rng, a.device)
        loss = F.cross_entropy(fwd(x).flatten(0, 1), y.flatten())
        opt.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        if step % a.log_every == 0 or step == a.steps:
            vl = quick_val(fwd, val, a.length, a.device)
            print(f'step {step} train_bpb {bpb(loss.item()):.4f} qat_val_bpb {vl:.4f} '
                  f't {time.time() - t0:.0f}s', flush=True)
    save_checkpoint(a.out, model.eval(), qat=vars(a))


if __name__ == '__main__':
    main()
