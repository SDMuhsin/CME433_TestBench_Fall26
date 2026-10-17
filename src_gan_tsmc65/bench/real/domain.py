"""Fashion-MNIST-specific secondary metrics, using classifier/fmnist_cnn.

  cnn_fid  : FID on the CNN's 128-d penultimate features (after ReLU) vs the 60k train set
  nn_psnr  : per generated image, the max PSNR over the 10k real test images (its nearest real
             image in pixel space); mean and median over the set
  nn_label : fraction whose nearest real image's label equals the classifier label of the image
  cnn_is   : exp(E_x KL(p(y|x) || p(y))) with the CNN, whole set; max 10
  conf     : mean max softmax probability;  entropy: entropy (bits) of the label histogram, max 3.32
"""
import numpy as np
import torch
from scipy import linalg

from ...classifier.net import load


def _x(u8, dev):
    return torch.from_numpy(np.asarray(u8, np.float32).reshape(-1, 1, 28, 28) / 255.0).to(dev)


@torch.no_grad()
def cnn_outputs(u8, dev, bs=2000):
    """-> (penultimate features [N, 128] float64, softmax [N, 10] float64)."""
    net = load().to(dev)
    feats, probs = [], []
    for i in range(0, len(u8), bs):
        f = net[:-1](_x(u8[i:i + bs], dev))
        feats.append(f.double().cpu())
        probs.append(torch.softmax(net[-1](f), 1).double().cpu())
    return torch.cat(feats).numpy(), torch.cat(probs).numpy()


def frechet(f1, f2):
    m1, m2 = f1.mean(0), f2.mean(0)
    c1, c2 = np.cov(f1, rowvar=False), np.cov(f2, rowvar=False)
    covmean = linalg.sqrtm(c1 @ c2).real
    return float(((m1 - m2) ** 2).sum() + np.trace(c1 + c2 - 2 * covmean))


@torch.no_grad()
def nearest_real(gen_u8, real_u8, dev, bs=1000):
    """-> (max PSNR over real per generated image [N], index of that real image [N])."""
    r = torch.from_numpy(real_u8.reshape(len(real_u8), -1)).to(dev, torch.float64)
    rn = (r * r).sum(1)
    best, idx = [], []
    for i in range(0, len(gen_u8), bs):
        g = torch.from_numpy(gen_u8[i:i + bs].reshape(-1, 784)).to(dev, torch.float64)
        d = (g * g).sum(1, keepdim=True) + rn[None] - 2 * g @ r.T
        v, j = d.min(1)
        best.append(v.clamp_min(0).cpu() / 784)
        idx.append(j.cpu())
    mse = torch.cat(best).numpy()
    psnr = np.where(mse == 0, np.inf, 10 * np.log10(255.0 ** 2 / np.maximum(mse, 1e-12)))
    return psnr, torch.cat(idx).numpy()


def domain_metrics(gen_u8, train_feats, test_u8, test_labels, dev, nn_u8=None):
    """nn_u8: images for the nearest-neighbour metrics if not gen_u8 (used for the real-data row)."""
    f, p = cnn_outputs(gen_u8, dev)
    lab = p.argmax(1)
    nn_u8 = gen_u8 if nn_u8 is None else nn_u8
    psnr, j = nearest_real(nn_u8, test_u8, dev)
    nn_lab = lab if nn_u8 is gen_u8 else cnn_outputs(nn_u8, dev)[1].argmax(1)
    py = p.mean(0)
    kl = (p * (np.log(p + 1e-12) - np.log(py + 1e-12))).sum(1).mean()
    h = np.bincount(lab, minlength=10) / len(lab)
    return dict(cnn_fid=frechet(f, train_feats),
                nn_psnr_mean=float(np.mean(psnr)), nn_psnr_median=float(np.median(psnr)),
                nn_label=float((test_labels[j] == nn_lab).mean()),
                cnn_is=float(np.exp(kl)), conf=float(p.max(1).mean()),
                entropy=float(-(h[h > 0] * np.log2(h[h > 0])).sum()))
