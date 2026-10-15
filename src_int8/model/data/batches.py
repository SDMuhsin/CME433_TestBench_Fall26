"""Random training crops and the fixed evaluation crops shared by every evaluator."""
import numpy as np


def sample_batch(data, batch, length, rng):
    """Random crops: (inputs, targets) uint8 arrays of shape [batch, length]."""
    starts = rng.integers(0, len(data) - length - 1, size=batch)
    seq = np.stack([data[s:s + length + 1] for s in starts])
    return seq[:, :-1], seq[:, 1:]


def eval_segments(data, n, length, seed=1234):
    """Fixed evaluation crops [n, length + 1]; seed 1234 = the FP16 chip's validation set."""
    rng = np.random.default_rng(seed)
    starts = rng.integers(0, len(data) - length - 1, size=n)
    return np.stack([data[s:s + length + 1] for s in starts]).astype(np.int64)
