"""Model-level: stream-driven == parameter-driven, determinism, state reset, accumulator bounds
on random worst-case parameters, INT24 state never saturates on text, greedy text sanity."""
import numpy as np

from src_int8.golden.host.generate import generate
from src_int8.golden.host.sampler import HostSampler
from src_int8.golden.io.stream import token_stream
from src_int8.golden.model import HwModel
from src_int8.golden.ops.formats import ACT

from .conftest import CFG, random_params


def test_stream_driven_matches_param_driven(shipped):
    cfg, P = shipped
    a, b = HwModel(cfg, P), HwModel(cfg, P)
    for t in b'Once upon a time':
        assert np.array_equal(a.step([t]), b.step_stream(token_stream(P, t)))
    assert all(np.array_equal(x, y) for x, y in zip(a.h, b.h))


def test_batched_equals_single_and_reset(shipped):
    cfg, P = shipped
    texts = [b'Lily saw a dog.', b'The sun was hot']
    batched = HwModel(cfg, P, batch=2)
    singles = [HwModel(cfg, P) for _ in texts]
    for i in range(len(texts[0])):
        zb = batched.step([t[i] for t in texts])
        for k, s in enumerate(singles):
            assert np.array_equal(zb[k], s.step([texts[k][i]])[0])
    batched.reset()
    assert all(not h.any() for h in batched.h) and all(not c.any() for c in batched.conv)
    fresh = HwModel(cfg, P, batch=2)
    assert np.array_equal(batched.step([65, 66]), fresh.step([65, 66]))


def test_logits_and_state_within_formats(shipped):
    cfg, P = shipped
    m = HwModel(cfg, P)
    hmax = 0
    for t in b'Once upon a time, there was a little girl named Lily. She loved to play outside.':
        z = m.step([t])
        assert z.min() >= ACT['LOGITS'].lo and z.max() <= ACT['LOGITS'].hi
        hmax = max(hmax, max(int(np.abs(h).max()) for h in m.h))
    assert hmax < ACT['H'].hi, 'INT24 state saturated'


def test_random_params_run_without_accumulator_overflow():
    """Random legal integer parameters and tokens never trip a lane bound assertion."""
    rng = np.random.default_rng(11)
    P = random_params(rng)
    m = HwModel(CFG, P, batch=8)
    for _ in range(20):
        z = m.step(rng.integers(0, 128, 8))
        assert z.shape == (8, 128)


def test_greedy_generation_is_ascii_text(shipped):
    cfg, P = shipped
    text = generate(cfg, P, 'Once upon a time', 40, HostSampler(temperature=0))
    assert text and all(c == 10 or 32 <= c < 127 for c in text)


def test_sampler_is_seeded_and_greedy_is_argmax():
    z = np.array([0, 1000, -5, 1000]) * 1
    assert HostSampler(0)(z) == 1
    a = [HostSampler(0.8, 3)(np.arange(128) * 10) for _ in range(5)]
    b = [HostSampler(0.8, 3)(np.arange(128) * 10) for _ in range(5)]
    assert a == b
