"""Bits per byte of a checkpoint on the fixed evaluation crops: float forward or QAT fake-quant.

python3 -m src_int8.model.evaluate <ckpt> <val.bin> [--qat] [--n 256 --length 1024]
"""
import argparse
import math

import torch
import torch.nn.functional as F

from .data import eval_segments, load_bin
from .qat.qmamba import q_forward
from .train.common import load_checkpoint


@torch.no_grad()
def bits_per_byte(forward, segs, device, batch=64):
    """Mean next-byte cross-entropy in bits over segs [n, L+1] (state reset per crop)."""
    total, count = 0.0, 0
    for i in range(0, len(segs), batch):
        s = torch.as_tensor(segs[i:i + batch], device=device)
        logits = forward(s[:, :-1]).float()
        total += F.cross_entropy(logits.flatten(0, 1), s[:, 1:].flatten(), reduction='sum').item()
        count += s[:, 1:].numel()
    return total / count / math.log(2)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('ckpt')
    ap.add_argument('val_bin')
    ap.add_argument('--qat', action='store_true', help='fake-quantised forward (spec section 9)')
    ap.add_argument('--n', type=int, default=256)
    ap.add_argument('--length', type=int, default=1024)
    ap.add_argument('--device', default='cuda:1')
    a = ap.parse_args()
    model = load_checkpoint(a.ckpt, a.device)
    fwd = (lambda t: q_forward(model, t)) if a.qat else model
    segs = eval_segments(load_bin(a.val_bin), a.n, a.length)
    print(f'{"qat" if a.qat else "float"} bpb {bits_per_byte(fwd, segs, a.device):.4f}')


if __name__ == '__main__':
    main()
