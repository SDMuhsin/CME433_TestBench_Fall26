"""Host-side sampler: FP16 logits read back from the chip -> next byte (fixed-seed RNG)."""
import numpy as np

from ..arith.fp import value


class HostSampler:
    """Greedy when temperature == 0, else softmax(logits / T) sampling (float64)."""

    def __init__(self, temperature=0.8, seed=0):
        self.temperature = temperature
        self.rng = np.random.default_rng(seed)

    def __call__(self, logit_bits):
        z = value(logit_bits).astype(np.float64)
        if self.temperature == 0:
            return int(np.argmax(z))
        p = np.exp((z - z.max()) / self.temperature)
        return int(self.rng.choice(len(p), p=p / p.sum()))
