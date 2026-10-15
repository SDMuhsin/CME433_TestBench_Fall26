"""Train the byte-level Mamba LM on TinyStories (AdamW, warmup + cosine LR)."""
import argparse
import json
import math
import time

import numpy as np
import torch
import torch.nn.functional as F

from .config import ModelConfig
from .data import load_bin, sample_batch
from .mamba import MambaLM


def load_checkpoint(path, device='cpu'):
    ck = torch.load(path, map_location=device)
    model = MambaLM(ModelConfig(**ck['config'])).to(device)
    model.load_state_dict(ck['model'])
    return model.eval()


def lr_at(step, steps, peak, warmup=500):
    if step < warmup:
        return peak * step / warmup
    return peak * 0.5 * (1 + math.cos(math.pi * (step - warmup) / max(1, steps - warmup)))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--train-bin', required=True)
    ap.add_argument('--val-bin', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--d-inner', type=int, default=64)
    ap.add_argument('--steps', type=int, default=20000)
    ap.add_argument('--batch', type=int, default=64)
    ap.add_argument('--length', type=int, default=512)
    ap.add_argument('--lr', type=float, default=3e-3)
    ap.add_argument('--device', default='cuda:0')
    ap.add_argument('--seed', type=int, default=0)
    a = ap.parse_args()

    torch.manual_seed(a.seed)
    rng = np.random.default_rng(a.seed)
    cfg = ModelConfig(d_inner=a.d_inner)
    model = MambaLM(cfg).to(a.device)
    step_model = torch.compile(model)
    nparam = sum(p.numel() for p in model.parameters())
    opt = torch.optim.AdamW(model.parameters(), lr=a.lr, weight_decay=0.01, betas=(0.9, 0.95))
    train, val = load_bin(a.train_bin), load_bin(a.val_bin)
    print(json.dumps({'config': cfg.to_dict(), 'params': nparam, 'args': vars(a)}), flush=True)

    t0 = time.time()
    for step in range(a.steps + 1):
        for g in opt.param_groups:
            g['lr'] = lr_at(step, a.steps, a.lr)
        x, y = (torch.as_tensor(v.astype(np.int64), device=a.device)
                for v in sample_batch(train, a.batch, a.length, rng))
        loss = F.cross_entropy(step_model(x).flatten(0, 1), y.flatten())
        opt.zero_grad(set_to_none=True)
        loss.backward()
        torch.nn.utils.clip_grad_norm_(model.parameters(), 1.0)
        opt.step()
        if step % 500 == 0:
            with torch.no_grad():
                vx, vy = (torch.as_tensor(v.astype(np.int64), device=a.device)
                          for v in sample_batch(val, 64, a.length, np.random.default_rng(7)))
                vl = F.cross_entropy(model.eval()(vx).flatten(0, 1), vy.flatten()).item()
                model.train()
            print(f'step {step} train_bpb {loss.item() / math.log(2):.4f} '
                  f'val_bpb {vl / math.log(2):.4f} t {time.time() - t0:.0f}s', flush=True)
    torch.save({'config': cfg.to_dict(), 'model': model.state_dict()}, a.out)


if __name__ == '__main__':
    main()
