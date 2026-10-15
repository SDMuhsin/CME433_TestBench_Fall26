"""The integer parameter set: key layout, dtypes, range checks, .npz load / save.

P = {'E_in': int16 [V, D] Q7.8, 'E_out': int8 [V, D], 'rq_logits': [V, 2] (M, s),
     'layers': [ {LAYER_KEYS...} ] }; every array is int64 in memory.
RQ pairs are int arrays [rows, 2] with columns (M, s).
"""
import json

import numpy as np

from ..ops.formats import A2_HI, A2_LO, M_HI, M_LO, PARAM, S_HI, S_LO, W_MAX

LAYER_KEYS = ('W_in_x', 'rq_in_x', 'conv_w0', 'conv_w1', 'rq_conv', 'cb', 'W_x', 'rq_x', 'b_dt',
              'W_dt', 'rq_dt', 'A2', 'D', 'W_in_z', 'rq_z', 'W_out', 'rq_out')
WEIGHTS = ('W_in_x', 'conv_w0', 'conv_w1', 'W_x', 'W_dt', 'W_in_z', 'W_out')
FIXED = {'cb': 'CB', 'b_dt': 'B_DT', 'D': 'D', 'A2': 'A2'}        # key -> PARAM format
RQS = ('rq_in_x', 'rq_conv', 'rq_x', 'rq_dt', 'rq_z', 'rq_out')
A2_INT = (int(A2_LO * 2 ** PARAM['A2'].frac), int(A2_HI * 2 ** PARAM['A2'].frac))   # [-32768, -1]


def shapes(cfg):
    D, E, V, R, N = cfg['d_model'], cfg['d_inner'], cfg['vocab'], cfg['dt_rank'], cfg['d_state']
    layer = dict(W_in_x=(E, D), rq_in_x=(E, 2), conv_w0=(E,), conv_w1=(E,), rq_conv=(E, 2), cb=(E,),
                 W_x=(R + 2 * N, E), rq_x=(R + 2 * N, 2), b_dt=(E,), W_dt=(E, R), rq_dt=(E, 2),
                 A2=(E, N), D=(E,), W_in_z=(E, D), rq_z=(E, 2), W_out=(D, E), rq_out=(D, 2))
    return dict(E_in=(V, D), E_out=(V, D), rq_logits=(V, 2)), layer


def _in_range(v, lo, hi):
    return bool(np.all((v >= lo) & (v <= hi)))


def check_ranges(P, cfg):
    """Assert every range of spec 3.2 and the shapes of the parameter set."""
    top, layer = shapes(cfg)
    e_in = PARAM['E_IN']
    assert P['E_in'].shape == top['E_in'] and _in_range(P['E_in'], e_in.lo, e_in.hi)
    assert P['E_out'].shape == top['E_out'] and _in_range(P['E_out'], -W_MAX, W_MAX)
    _check_rq(P['rq_logits'], top['rq_logits'])
    assert len(P['layers']) == cfg['n_layer']
    for L in P['layers']:
        assert set(L) == set(LAYER_KEYS), set(L) ^ set(LAYER_KEYS)
        for k in LAYER_KEYS:
            assert L[k].shape == layer[k], (k, L[k].shape)
        for k in WEIGHTS:
            assert _in_range(L[k], -W_MAX, W_MAX), k
        for k, f in FIXED.items():
            fmt = PARAM[f]
            lo, hi = A2_INT if k == 'A2' else (fmt.lo, fmt.hi)
            assert _in_range(L[k], lo, hi), k
        for k in RQS:
            _check_rq(L[k], layer[k])
    return True


def _check_rq(rq, shape):
    assert rq.shape == shape
    assert _in_range(rq[:, 0], M_LO, M_HI - 1) and _in_range(rq[:, 1], S_LO, S_HI), 'RQ range'


def _store_dtype(key):
    if key.startswith('rq_'):
        return np.int32
    if key in ('E_in', 'cb', 'b_dt', 'A2'):
        return np.int16
    return np.int8


def save_params(path, P, cfg):
    check_ranges(P, cfg)
    flat = {k: P[k].astype(_store_dtype(k)) for k in ('E_in', 'E_out', 'rq_logits')}
    for l, L in enumerate(P['layers']):
        flat.update({f'{k}.{l}': L[k].astype(_store_dtype(k)) for k in LAYER_KEYS})
    np.savez(path, config=json.dumps(cfg), **flat)


def load_params(path):
    """-> (cfg, P) with int64 arrays; the spec 3.2 ranges are re-asserted on load."""
    z = np.load(path)
    cfg = json.loads(str(z['config']))
    i64 = lambda k: z[k].astype(np.int64)
    P = {'E_in': i64('E_in'), 'E_out': i64('E_out'), 'rq_logits': i64('rq_logits'),
         'layers': [{k: i64(f'{k}.{l}') for k in LAYER_KEYS} for l in range(cfg['n_layer'])]}
    check_ranges(P, cfg)
    return cfg, P
