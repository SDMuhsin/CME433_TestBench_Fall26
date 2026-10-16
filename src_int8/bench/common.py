"""Shared pieces of the benchmark: the evaluation crops and per-position NLL from INT16 logits."""
import numpy as np

from ..golden.host.evaluate import nll
from ..golden.host.sampler import logits_to_float
from ..model.data import eval_segments, load_bin

PARAMS = 'src_int8/golden/params/mamba_e96_int8.npz'
SEED = 1234                    # the crop seed of every BPB number in docs/model.md


def crops(val_bin, n, length):
    """[n, length + 1] byte crops of the held-out split (same as golden.host.evaluate)."""
    return eval_segments(load_bin(val_bin), n, length, SEED)


def nll_bits(logits, seg):
    """logits [L, V] INT16 for inputs seg[:L] -> -log2 p(seg[t + 1]) [L] (float64)."""
    return nll(logits_to_float(logits), seg[1:len(logits) + 1]) / np.log(2)
