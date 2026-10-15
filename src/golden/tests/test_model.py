"""Shipped FP16 parameters: stream-driven chip view equals the parameter view; greedy regression."""
from pathlib import Path

import numpy as np

from src.golden.host.generate import generate
from src.golden.net.model import HwModel
from src.golden.host.sampler import HostSampler
from src.golden.data.stream import token_stream
from src.golden.data.weights import load_params

PARAMS = Path(__file__).resolve().parents[1] / 'params' / 'mamba_e96_fp16.npz'


def test_stream_driven_matches_param_driven():
    cfg, P = load_params(PARAMS)
    a, b = HwModel(cfg, P), HwModel(cfg, P)
    for t in b'Once upon':
        assert np.array_equal(a.step([t]), b.step_stream(token_stream(P, t)))


def test_greedy_generation_is_ascii_text():
    cfg, P = load_params(PARAMS)
    text = generate(cfg, P, 'Once upon a time', 40, HostSampler(temperature=0))
    assert text and all(c == 10 or 32 <= c < 127 for c in text)
