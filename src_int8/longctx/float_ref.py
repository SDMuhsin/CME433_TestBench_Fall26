"""Float64 recurrent reference of the QAT checkpoint: the trained function with exact math
(no fake quantisation), token by token, so its state h [b, E, N] is directly comparable with
the golden INT24 state.  Uses the exporter's folded float64 parameters."""
import numpy as np

from ..golden.io.weights import load_float_params
from ..model.config import EPS


def _rmsnorm(x):
    return x / np.sqrt(np.mean(x * x, -1, keepdims=True) + EPS)


def _silu(x):
    return x / (1.0 + np.exp(-x))


class FloatModel:
    """Batched float64 recurrence mirroring src_int8.golden.model.HwModel (same op structure)."""

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
            u = _silu(L['cb'] + L['conv_w0'] * self.conv[l] + L['conv_w1'] * xi)
            self.conv[l] = xi
            dbc = u @ L['W_x'].T
            dt = np.minimum(np.logaddexp(0.0, dbc[:, :R] @ L['W_dt'].T + L['b_dt']), 8.0)
            B, C = dbc[:, R:R + N], dbc[:, R + N:]
            dA = np.exp2(dt[..., None] * L['A2'])
            self.h[l] = dA * self.h[l] + (dt * u)[..., None] * B[:, None, :]
            y = np.einsum('ben,bn->be', self.h[l], C) + L['D'] * u
            x = x + (y * _silu(xn @ L['W_in_z'].T)) @ L['W_out'].T
        return _rmsnorm(x) @ self.P['E_out'].T


def load(ckpt):
    """-> (cfg, folded float64 params) for FloatModel."""
    return load_float_params(ckpt)
