"""Standard GAN metrics through torch-fidelity 0.4.0 (Obukhov et al.), against the 60k train set.

Inputs are uint8 28x28 greyscale, replicated to 3 channels; torch-fidelity's extractors resize
internally with TF1-compatible bilinear interpolation (Inception-v3 to 299x299, VGG-16 to 224x224).
  FID, KID : Inception-v3 pool3 (2048-d), TF-ported FID weights; KID = 100 subsets of 1000, poly-3
  IS       : Inception-v3 logits, 10 splits
  P / R    : precision / recall of Kynkaenniemi et al. 2019, VGG-16 fc2 features, k = 3, against
             a fixed random train subset of the same size as the generated set (equal N, as in the paper)
The train-set features are cached under build/gan65/fidelity_cache. GAN65_FID_BATCH (default 500)
sets the extractor batch size, for a shared GPU; the features are per image, so it does not
change the metrics.
"""
import os

import numpy as np
import torch
from torch.utils.data import Dataset

from ...common.paths import BUILD

BATCH = int(os.environ.get('GAN65_FID_BATCH', 500))


class Grey3(Dataset):
    def __init__(self, u8):
        self.x = torch.from_numpy(np.ascontiguousarray(u8)).unsqueeze(1)

    def __len__(self):
        return len(self.x)

    def __getitem__(self, i):
        return self.x[i].expand(3, -1, -1).contiguous()


def _calc(gen_u8, ref_u8, cache, device, **metrics):
    import torch_fidelity
    torch.cuda.set_device(torch.device(device))
    return torch_fidelity.calculate_metrics(
        input1=Grey3(gen_u8), input2=Grey3(ref_u8), cuda=True, batch_size=BATCH, verbose=False,
        input2_cache_name=cache, cache_root=str(BUILD / 'fidelity_cache'), **metrics)


def gan_metrics(gen_u8, train_u8, device, prc_seed=0):
    m = _calc(gen_u8, train_u8, f'fmnist_train{len(train_u8)}', device, isc=True, fid=True, kid=True)
    n = len(gen_u8)
    sub = np.random.default_rng(prc_seed).permutation(len(train_u8))[:n]
    p = _calc(gen_u8, train_u8[sub], f'fmnist_train_sub{n}_seed{prc_seed}', device, prc=True)
    return dict(fid=m['frechet_inception_distance'],
                is_mean=m['inception_score_mean'], is_std=m['inception_score_std'],
                kid_mean=m['kernel_inception_distance_mean'], kid_std=m['kernel_inception_distance_std'],
                precision=p['precision'], recall=p['recall'])
