"""Token-by-token hardware model: token (or its stream) in, INT16 Q7.8 logits out, integer state."""
import numpy as np

from .io.stream import unpack_stream
from .layers.block import final_logits, mamba_block


class HwModel:
    """Batched recurrent golden model; state per layer: conv [b, E] INT8 and h [b, E, N] INT24."""

    def __init__(self, cfg, params, batch=1):
        self.cfg, self.P = cfg, params
        self.batch = batch
        self.reset()

    def reset(self):
        """CTRL.STATE_RESET: zero H0, H1, CONV0, CONV1."""
        E, N = self.cfg['d_inner'], self.cfg['d_state']
        self.conv = [np.zeros((self.batch, E), np.int64) for _ in self.P['layers']]
        self.h = [np.zeros((self.batch, E, N), np.int64) for _ in self.P['layers']]

    def step(self, tokens, probes=None):
        """tokens [b] ints -> logits [b, vocab] INT16 (Q7.8). probes: optional list to fill per layer."""
        return self._forward(self.P['E_in'][np.asarray(tokens)], self.P, probes)

    def step_stream(self, stream):
        """Chip view (batch 1): one token's byte stream -> logits [1, vocab]."""
        emb, Q = unpack_stream(stream, self.cfg)
        return self._forward(emb[None], Q)

    def _forward(self, x, P, probes=None):
        for l, L in enumerate(P['layers']):
            probe = {} if probes is not None else None
            x, self.conv[l], self.h[l] = mamba_block(x, self.conv[l], self.h[l], L, self.cfg, probe)
            if probes is not None:
                probes.append(probe)
        return final_logits(x, P['E_out'], P['rq_logits'])
