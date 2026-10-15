"""Spec 3.2 / 3.3: per-row quantisation, (M, s) encoding, exporter range asserts."""
import numpy as np
import pytest

from src_int8.golden.io.params import check_ranges
from src_int8.golden.io.weights import encode_rq, q_fixed, q_rows, quantise, round_half_up, rq_for
from src_int8.golden.ops.formats import PARAM

from .conftest import CFG


def test_round_half_up():
    assert round_half_up([0.5, 1.5, -0.5, -1.5, 2.4999, -2.5]).tolist() == [1, 2, 0, -1, 2, -2]


def test_q_rows_scale_rule_and_zero_row():
    w = np.array([[0.5, -1.0, 0.25], [0.0, 0.0, 0.0], [3.0, 3.0, -3.0]])
    q, s = q_rows(w)
    assert s.tolist() == [1.0 / 127, 1.0, 3.0 / 127]
    assert q.tolist() == [[64, -127, 32], [0, 0, 0], [127, 127, -127]]


def test_encode_rq_octaves_and_carry():
    for r in (2 ** -33, 0.001, 0.5, 1.0, 1.99, 7.3, 2 ** 13):
        M, s = encode_rq(np.array([r]))[0]
        assert 1 << 14 <= M < 1 << 15 and 1 <= s <= 47
        assert abs(M / 2 ** s - r) / r < 2 ** -14
    M, s = encode_rq(np.array([(2 ** 15 - 0.4) / 2 ** 15]))[0]       # rounds up to 2^15 -> carry
    assert (M, s) == (1 << 14, 14)
    with pytest.raises(AssertionError):
        encode_rq(np.array([2 ** 14]))                                 # s would be 0


def test_rq_for_uses_spec_scales():
    s_w = np.array([1.0 / 127])
    M, s = rq_for(s_w, 'in_x')[0]                                      # r = s_w * 2^-5 / 2^-4
    assert abs(M / 2 ** s - s_w[0] / 2) < s_w[0] / 2 * 2 ** -14
    M, s = rq_for(s_w, 'logits')[0]                                    # r = s_w * 2^-5 / 2^-8 = 8 s_w
    assert abs(M / 2 ** s - 8 * s_w[0]) < 8 * s_w[0] * 2 ** -14


def test_q_fixed_saturates():
    assert q_fixed([200.0, -200.0, 0.00390625], PARAM['CB']).tolist() == [32767, -32768, 1]
    assert q_fixed([3.0, -3.0, 0.5], PARAM['D']).tolist() == [127, -128, 32]


def test_quantise_random_float_params_passes_asserts():
    rng = np.random.default_rng(0)
    D, E, R, N, V = 64, 96, 4, 4, 128
    layer = lambda: {'W_in_x': rng.normal(0, 0.3, (E, D)), 'W_in_z': rng.normal(0, 0.3, (E, D)),
                     'cb': rng.normal(0, 1, E), 'conv_w0': rng.normal(0, 0.5, E), 'conv_w1': rng.normal(0, 0.5, E),
                     'W_x': rng.normal(0, 0.3, (R + 2 * N, E)), 'W_dt': rng.normal(0, 1, (E, R)),
                     'b_dt': rng.normal(-3, 1, E), 'A2': -np.exp(rng.normal(0, 1, (E, N))) * 1.44,
                     'D': rng.uniform(0.1, 1.7, E), 'W_out': rng.normal(0, 0.2, (D, E))}
    Pf = {'E_in': rng.normal(0, 1, (V, D)), 'E_out': rng.normal(0, 1, (V, D)), 'layers': [layer(), layer()]}
    P = quantise(Pf, CFG)
    assert check_ranges(P, CFG)
    assert np.all(P['layers'][0]['A2'] <= -1)


def test_shipped_params_ranges(shipped):
    cfg, P = shipped
    assert check_ranges(P, cfg)
    for L in P['layers']:
        assert np.abs(L['W_in_x']).max(-1).min() == 127         # every row uses the full INT8 range
        assert np.abs(L['W_out']).max(-1).min() == 127
