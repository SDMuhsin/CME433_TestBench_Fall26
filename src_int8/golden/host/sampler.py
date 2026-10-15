"""Host-side sampler: INT16 Q7.8 logits read back from the chip -> next byte (fixed-seed RNG)."""
import numpy as np

from ..ops.formats import ACT

LOGIT_SCALE = ACT['LOGITS'].scale    # the host divides by 256


def logits_to_float(logit_ints):
    return np.asarray(logit_ints, dtype=np.float64) * LOGIT_SCALE


class HostSampler:
    """Greedy when temperature == 0, else softmax(logits / T) sampling (float64)."""

    def __init__(self, temperature=0.8, seed=0):
        self.temperature = temperature
        self.rng = np.random.default_rng(seed)

    def __call__(self, logit_ints):
        z = logits_to_float(logit_ints)
        if self.temperature == 0:
            return int(np.argmax(z))
        p = np.exp((z - z.max()) / self.temperature)
        return int(self.rng.choice(len(p), p=p / p.sum()))
