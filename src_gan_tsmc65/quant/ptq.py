"""Post-training quantisation of the float G300 Fashion-MNIST generator (model/fmnist/G300_float.npz)
to the chip's D-bit integer pipeline, D = 8 or 16 (docs/width16.md s.3).

The scheme of the committed INT8 model (it reproduces model/fmnist bit for bit, quant/check.py):
  * weights, biases : per tensor, symmetric, s = r * max|w| / Q with Q = 2^(D-1) - 1,
                      q = clamp(round(w / s), -Q, Q); r = the clip ratio of the tensor
  * latent z        : sZ = p99.99(|z|) / Q over 512 calibration latents (torch seed 1000),
                      zq = clamp(round(z / sZ), -Q, Q)
  * hidden h0, h2   : static calibration, sH = p99.99(h) / Q of the float layer output computed
                      from the previous layer's integer chip output (dequantised) through the
                      dequantised weights; ReLU outputs, so the codes are 0 .. Q (no zero point)
  * requant         : MA = round(sW sX / sY 2^S), MB = round(sb / sY 2^S) (ReLU layers);
                      MW4 = round(sW4 sH2 2^(20+S)), MB4 = round(sb4 2^(20+S)) (Q20 tanh input)
  * S               : 16 for INT8; for another width the largest S whose six M fit the 32-bit CSRs
"""
import numpy as np

from ..golden.model import affine_shift, matvec, relu_rq

N_CAL, CAL_SEED, PCT = 512, 1000, 99.99
CLIP_INT8 = {'0.weight': 0.9, '0.bias': 1.0, '2.weight': 0.65, '2.bias': 1.0, '4.weight': 0.4, '4.bias': 1.0}
CLIP_INT16 = {k: 1.0 for k in CLIP_INT8}          # docs/width16.md: clipping only adds error at 16 bits
M_MAX = (1 << 32) - 1


def qmax(width):
    return (1 << (width - 1)) - 1


def tensor_scale(w, ratio, width):
    """clip threshold r * max|w| in float32 (the tensors' precision), then / Q in float64"""
    return float(np.float32(np.abs(w).max()) * np.float32(ratio)) / qmax(width)


def quantise(x, s, width):
    q = qmax(width)
    return np.clip(np.round(np.asarray(x, np.float64) / s), -q, q).astype(np.int64)


def cal_latents(n=N_CAL, seed=CAL_SEED):
    import torch
    return torch.randn(n, 64, generator=torch.Generator().manual_seed(seed)).double().numpy()


def act_scale(h, width):
    return float(np.percentile(h, PCT) / qmax(width))


def csr_values(sc, s):
    """The six requant multipliers for shift s (scales dict sc)."""
    r = 1 << s
    return {'MA0': round(sc['0_weight'] * sc['sZ'] / sc['sH0'] * r), 'MB0': round(sc['0_bias'] / sc['sH0'] * r),
            'MA2': round(sc['2_weight'] * sc['sH0'] / sc['sH2'] * r), 'MB2': round(sc['2_bias'] / sc['sH2'] * r),
            'MW4': round(sc['4_weight'] * sc['sH2'] * r * (1 << 20)), 'MB4': round(sc['4_bias'] * r * (1 << 20))}


def pick_shift(sc, width):
    if width == 8:
        return 16
    s = 16
    while max(csr_values(sc, s + 1).values()) <= M_MAX:
        s += 1
    return s


def quantise_model(fw, width, clip):
    """fw: float npz dict -> (int model dict for golden.model, scales, S)."""
    m = dict(width=width, acc_w=2 * width + 8)
    sc = {}
    for n in (0, 2, 4):
        for t in ('weight', 'bias'):
            w = fw[f'{n}_{t}']
            sc[f'{n}_{t}'] = tensor_scale(w, clip[f'{n}.{t}'], width)
            m[f'{"W" if t == "weight" else "b"}{n}'] = quantise(w, sc[f'{n}_{t}'], width)
    deq = {k: m[f'{k[0]}{k[1]}'] * sc[f'{k[1]}_{"weight" if k[0] == "W" else "bias"}']
           for k in (('W', 0), ('b', 0), ('W', 2), ('b', 2))}
    z = cal_latents()
    sc['sZ'] = act_scale(np.abs(z), width)
    zq = quantise(z, sc['sZ'], width)
    h0f = np.maximum((zq * sc['sZ']) @ deq['W', 0].T + deq['b', 0], 0)
    sc['sH0'] = act_scale(h0f, width)
    # h0 of the integer chip needs MA0 / MB0, which do not depend on sH2: any shift works here
    s = 16
    while True:                                   # S is fixed once sH2 is known; iterate to a fixed point
        part = dict(sc, sH2=1.0)
        m.update(S=s, **{k: v for k, v in csr_values(part, s).items() if k in ('MA0', 'MB0')})
        h0 = relu_rq(matvec(m['W0'], zq, m['acc_w']), m['b0'], m['MA0'], m['MB0'], m)
        h2f = np.maximum((h0 * sc['sH0']) @ deq['W', 2].T + deq['b', 2], 0)
        sc['sH2'] = act_scale(h2f, width)
        s_new = pick_shift(sc, width)
        if s_new == s:
            break
        s = s_new
    m.update(csr_values(sc, s))
    return m, sc, s


def float_pixels(fw, z):
    """(tanh(G(z)) + 1) * 127.5 in float64, unrounded."""
    h = z
    for i in (0, 2):
        h = np.maximum(h @ fw[f'{i}_weight'].T.astype(np.float64) + fw[f'{i}_bias'], 0)
    return (np.tanh(h @ fw['4_weight'].T.astype(np.float64) + fw['4_bias']) + 1) * 127.5

