"""Shared training helpers: checkpoints, LR schedule, batches, quick validation."""
import math

import numpy as np
import torch
import torch.nn.functional as F

from ..config import ModelConfig
from ..data import sample_batch
from ..float.mamba import MambaLM


def load_checkpoint(path, device='cpu'):
    """.pt {'config', 'model'[, 'qat']} -> MambaLM in eval mode."""
    ck = torch.load(path, map_location=device)
    model = MambaLM(ModelConfig(**ck['config'])).to(device)
    model.load_state_dict(ck['model'])
    return model.eval()


def save_checkpoint(path, model, **extra):
    torch.save({'config': model.cfg.to_dict(), 'model': model.state_dict(), **extra}, path)


def lr_at(step, steps, peak, warmup):
    """Linear warm-up to `peak`, then cosine to 0."""
    if step < warmup:
        return peak * step / warmup
    return peak * 0.5 * (1 + math.cos(math.pi * (step - warmup) / max(1, steps - warmup)))


def batch_tensors(data, batch, length, rng, device):
    return tuple(torch.as_tensor(v.astype(np.int64), device=device)
                 for v in sample_batch(data, batch, length, rng))


def bpb(loss_nats):
    return loss_nats / math.log(2)


@torch.no_grad()
def quick_val(forward, val, length, device, batch=64, seed=7):
    """Cross-entropy in bits per byte on a fixed random batch of validation crops."""
    vx, vy = batch_tensors(val, batch, length, np.random.default_rng(seed), device)
    return bpb(F.cross_entropy(forward(vx).float().flatten(0, 1), vy.flatten()).item())
