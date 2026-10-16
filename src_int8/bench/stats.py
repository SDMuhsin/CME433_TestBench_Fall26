"""Crop-level statistics: every crop has the same length, so BPB = mean of the per-crop means."""
import numpy as np

BOOT = 4000
BOOT_SEED = 0


def bootstrap(per_crop):
    """per_crop [n] -> (mean, bootstrap SE, 95 % percentile CI) resampling whole crops."""
    x = np.asarray(per_crop, np.float64)
    rng = np.random.default_rng(BOOT_SEED)
    means = x[rng.integers(0, len(x), size=(BOOT, len(x)))].mean(1)
    lo, hi = np.percentile(means, [2.5, 97.5])
    return float(x.mean()), float(means.std(ddof=1)), (float(lo), float(hi))


def summary(nll):
    """nll [n, L] bits -> dict of BPB, PPL (per byte, 2^BPB), SE, CI."""
    m, se, ci = bootstrap(nll.mean(1))
    return dict(crops=int(nll.shape[0]), bytes=int(nll.size), bpb=m, bpb_se=se, bpb_ci95=ci,
                ppl=float(2 ** m), ppl_ci95=(float(2 ** ci[0]), float(2 ** ci[1])))


def paired(nll, base):
    """Same crops, two runs -> BPB difference (nll - base) with its paired bootstrap SE / CI."""
    m, se, ci = bootstrap(nll.mean(1) - base.mean(1))
    return dict(delta_bpb=m, delta_se=se, delta_ci95=ci)
