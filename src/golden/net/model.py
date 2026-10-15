"""Token-by-token hardware model: embedding row in, FP16 logits out, recurrent on-chip state."""
import numpy as np

from ..arith.fp import gemv
from .layers import mamba_block, rmsnorm
from ..data.stream import unpack_stream


class HwModel:
    """Batched recurrent golden model; state = per layer conv [b, E] and SSM h [b, E, N] (FP16)."""

    def __init__(self, cfg, params, batch=1):
        self.cfg, self.P = cfg, params
        E, N = cfg['d_inner'], cfg['d_state']
        self.conv = [np.zeros((batch, E), np.uint16) for _ in params['layers']]
        self.h = [np.zeros((batch, E, N), np.uint16) for _ in params['layers']]

    def step(self, tokens):
        """tokens [b] ints -> logits [b, vocab] FP16 bits."""
        return self._forward(self.P['E_in'][np.asarray(tokens)], self.P)

    def step_stream(self, words):
        """Chip view (batch 1): one token's host word stream -> logits [1, vocab] FP16 bits."""
        emb, Q = unpack_stream(np.asarray(words, np.uint16), self.cfg)
        return self._forward(emb[None], Q)

    def _forward(self, x, P):
        for l, L in enumerate(P['layers']):
            x, self.conv[l], self.h[l] = mamba_block(x, self.conv[l], self.h[l], L, self.cfg)
        return gemv(P['E_out'], rmsnorm(x))
