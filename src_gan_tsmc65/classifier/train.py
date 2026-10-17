"""Train the Fashion-MNIST labelling CNN (classifier/net.py) and write classifier/fmnist_cnn.npz.

python3 -m src_gan_tsmc65.classifier.train [--data build/gan65/data] [--device cuda:1] [--epochs 12]
Fashion-MNIST is downloaded by torchvision into --data if it is not already there.
"""
import argparse
import json
import time

import numpy as np
import torch
from torch import nn
from torchvision import datasets

from ..common.paths import BUILD
from .net import WEIGHTS, make_net, save


def tensors(root, train, dev):
    ds = datasets.FashionMNIST(root, train=train, download=True)
    x = ds.data.float().div(255.0).unsqueeze(1).to(dev)
    return x, ds.targets.to(dev)


def accuracy(net, x, y):
    net.eval()
    with torch.no_grad():
        return float(sum((net(x[i:i + 2000]).argmax(1) == y[i:i + 2000]).sum() for i in range(0, len(x), 2000)) / len(x))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--data', default=str(BUILD / 'data'))
    ap.add_argument('--device', default='cuda:1')
    ap.add_argument('--epochs', type=int, default=12)
    ap.add_argument('--seed', type=int, default=0)
    a = ap.parse_args()
    torch.manual_seed(a.seed)
    dev = torch.device(a.device)
    xtr, ytr = tensors(a.data, True, dev)
    xte, yte = tensors(a.data, False, dev)
    net = make_net().to(dev)
    opt = torch.optim.Adam(net.parameters(), 1e-3)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, a.epochs)
    loss_fn = nn.CrossEntropyLoss()
    t0 = time.time()
    for ep in range(a.epochs):
        net.train()
        perm = torch.randperm(len(xtr), device=dev)
        for i in range(0, len(xtr), 128):
            idx = perm[i:i + 128]
            xb = xtr[idx]
            shift = torch.randint(-2, 3, (2,)).tolist()          # light translation augmentation
            xb = torch.roll(xb, shifts=shift, dims=(2, 3))
            opt.zero_grad()
            loss_fn(net(xb), ytr[idx]).backward()
            opt.step()
        sched.step()
        print(f'epoch {ep + 1}: test acc {accuracy(net, xte, yte):.4f}  ({time.time() - t0:.0f} s)', flush=True)
    acc = accuracy(net, xte, yte)
    save(net.cpu())
    info = dict(test_accuracy=round(acc, 4), epochs=a.epochs, seed=a.seed, train_s=round(time.time() - t0, 1))
    WEIGHTS.with_suffix('.json').write_text(json.dumps(info, indent=1) + '\n')
    print(json.dumps(info))


if __name__ == '__main__':
    main()
