"""Float pre-training of the byte-level Mamba LM (the `src/model/train.py` recipe).

python3 -m src_int8.model.train.float --train-bin train.bin --val-bin val.bin --out e96.pt
"""
import argparse
import json
import time

import numpy as np
import torch
import torch.nn.functional as F

from ..config import ModelConfig
from ..data import load_bin
from ..float.mamba import MambaLM
from .common import batch_tensors, bpb, lr_at, quick_val, save_checkpoint


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--train-bin', required=True)
    ap.add_argument('--val-bin', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--d-inner', type=int, default=96)
    ap.add_argument('--steps', type=int, default=20000)
    ap.add_argument('--batch', type=int, default=64)
    ap.add_argument('--length', type=int, default=512)
    ap.add_argument('--lr', type=float, default=3e-3)
    ap.add_argument('--warmup', type=int, default=500)
    ap.add_argument('--device', default='cuda:0')
    ap.add_argument('--seed', type=int, default=0)
    a = ap.parse_args()

    torch.manual_seed(a.seed)
    rng = np.random.default_rng(a.seed)
    model = MambaLM(ModelConfig(d_inner=a.d_inner)).to(a.device)
    step_model = torch.compile(model)
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=0.01, betas=(0.9, 0.95))
    train, val = load_bin(a.train_bin), load_bin(a.val_bin)
    print(json.dumps({'config': model.cfg.to_dict(),
                      'params': sum(p.numel() for p in model.parameters()), 'args': vars(a)}),
          flush=True)
    t0 = time.time()
    for step in range(a.steps + 1):
        for g in opt.param_groups:
            g['lr'] = lr_at(step, a.steps, a.lr, a.warmup)
        x, y = batch_tensors(train, a.batch, a.length, rng, a.device)
        loss = F.cross_entropy(step_model(x).flatten(0, 1), y.flatten())
        opt.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        if step % 500 == 0:
            vl = quick_val(model.eval(), val, a.length, a.device)
            model.train()
            print(f'step {step} train_bpb {bpb(loss.item()):.4f} val_bpb {vl:.4f} '
                  f't {time.time() - t0:.0f}s', flush=True)
    save_checkpoint(a.out, model)


if __name__ == '__main__':
    main()
