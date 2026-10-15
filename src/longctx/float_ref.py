"""Float64 recurrent reference: the trained model token by token with exact math (no FP16).

Uses the exporter's folded float64 parameters (`src.golden.data.weights.fold_checkpoint`), so its
SSM state h [b, E, N] is directly comparable with the golden FP16 state.
"""
import numpy as np

from src.golden.data.weights import fold_checkpoint
from src.model.config import EPS


def load_float_params(ckpt):
    """.pt checkpoint -> (cfg, {'E_in', 'E_out', 'layers': [dict]}) in float64."""
    import torch
    ck = torch.load(ckpt, map_location='cpu')
    cfg = ck['config']
    P = fold_checkpoint({k: v.double().numpy() for k, v in ck['model'].items()}, cfg)
    keys = {k.rsplit('.', 1)[0] for k in P if '.' in k}
    layers = [{k: P[f'{k}.{l}'] for k in keys} for l in range(cfg['n_layer'])]
    return cfg, {'E_in': P['E_in'], 'E_out': P['E_out'], 'layers': layers}


def _rmsnorm(x):
    return x / np.sqrt(np.mean(x * x, -1, keepdims=True) + EPS)


def _silu(x):
    return x / (1.0 + np.exp(-x))


class FloatModel:
    """Batched float64 recurrence mirroring src.golden.net.model.HwModel (same op structure)."""

    def __init__(self, cfg, params, batch=1):
        self.cfg, self.P = cfg, params
        E, N = cfg['d_inner'], cfg['d_state']
        self.conv = [np.zeros((batch, E)) for _ in params['layers']]
        self.h = [np.zeros((batch, E, N)) for _ in params['layers']]

    def step(self, tokens):
        x = self.P['E_in'][np.asarray(tokens)]
        R, N = self.cfg['dt_rank'], self.cfg['d_state']
        for l, L in enumerate(self.P['layers']):
            xn = _rmsnorm(x)
            xi = xn @ L['W_in_x'].T
            u = _silu(L['conv_b'] + L['conv_w0'] * self.conv[l] + L['conv_w1'] * xi)
            self.conv[l] = xi
            dbc = u @ L['W_x'].T
            dt = np.logaddexp(0.0, dbc[:, :R] @ L['W_dt'].T + L['b_dt'])
            B, C = dbc[:, R:R + N], dbc[:, R + N:]
            dA = np.exp2(dt[..., None] * L['A2'])
            self.h[l] = dA * self.h[l] + (dt * u)[..., None] * B[:, None, :]
            y = np.einsum('ben,bn->be', self.h[l], C) + L['D'] * u
            x = x + (y * _silu(xn @ L['W_in_z'].T)) @ L['W_out'].T
        return _rmsnorm(x) @ self.P['E_out'].T
