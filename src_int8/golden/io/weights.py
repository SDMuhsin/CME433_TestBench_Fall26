"""Checkpoint -> integer parameter set (spec 3.2 / 3.3 / 9 export).

  fold:      block norm gain into W_in rows, final gain into E_out; A' = -exp(A_log) log2(e)
  quantise:  per-row INT8 weights (s_row = max|w| / 127), conv w0/w1 share a per-channel scale,
             D INT8 2^-6, A' Q8.7 clamped to [-256, -2^-7], cb / b_dt / E_in Q7.8
  requant:   r = s_w * s_in / s_out -> (M, s) with M in [2^14, 2^15), s in [1, 47]

python3 -m src_int8.golden.io.weights <ckpt.pt> <out.npz>
"""
import argparse
import math

import numpy as np

from ..ops.formats import A2_HI, A2_LO, ACT, M_HI, M_LO, PARAM, RQ_ROWS, S_HI, S_LO, W_MAX
from .params import check_ranges, save_params

LOG2E = math.log2(math.e)


def fold_checkpoint(state, cfg):
    """Float state dict (numpy float64) -> {'E_in', 'E_out', 'layers': [float64 tensors]}."""
    E = cfg['d_inner']
    emb = state['embed.weight']
    layers = []
    for l in range(cfg['n_layer']):
        s = {k[len(f'blocks.{l}.'):]: v for k, v in state.items() if k.startswith(f'blocks.{l}.')}
        W_in = s['in_proj.weight'] * s['norm.weight'][None, :]
        layers.append({'W_in_x': W_in[:E], 'W_in_z': W_in[E:], 'cb': s['conv_b'],
                       'conv_w0': s['conv_w'][:, 0], 'conv_w1': s['conv_w'][:, 1],
                       'W_x': s['x_proj.weight'], 'W_dt': s['dt_proj.weight'], 'b_dt': s['dt_proj.bias'],
                       'A2': -np.exp(s['A_log']) * LOG2E, 'D': s['D'], 'W_out': s['out_proj.weight']})
    return {'E_in': emb, 'E_out': emb * state['norm_f.weight'][None, :], 'layers': layers}


def round_half_up(x):
    return np.floor(np.asarray(x, dtype=np.float64) + 0.5).astype(np.int64)


def q_fixed(x, fmt):
    """Round to a fixed format and saturate to its range."""
    return np.clip(round_half_up(np.asarray(x) * 2.0 ** fmt.frac), fmt.lo, fmt.hi)


def row_scales(w):
    """s_row = max_k |w[row, k]| / 127 (1 for an all-zero row); w [..., rows, k]."""
    s = np.abs(w).max(-1) / W_MAX
    return np.where(s > 0, s, 1.0)


def q_rows(w):
    """-> (INT8 weights [rows, k], float64 scales [rows])."""
    s = row_scales(w)
    return np.clip(round_half_up(w / s[..., None]), -W_MAX, W_MAX), s


def encode_rq(r):
    """Exact ratio r (float64 array) -> int [rows, 2] of (M, s), spec 3.3."""
    r = np.asarray(r, dtype=np.float64)
    assert np.all(r > 0)
    s = 14 - np.floor(np.log2(r)).astype(np.int64)
    M = round_half_up(r * 2.0 ** s)
    carry = M == M_HI
    M[carry], s[carry] = M_LO, s[carry] - 1
    assert np.all((s >= S_LO) & (s <= S_HI)) and np.all((M >= M_LO) & (M < M_HI))
    return np.stack([M, s], -1)


def rq_for(s_w, row_class):
    s_in, s_out = (ACT[k].scale for k in RQ_ROWS[row_class])
    return encode_rq(s_w * s_in / s_out)


def quantise_layer(L):
    """Float64 folded layer -> integer layer with its RQ pairs."""
    Q = {}
    Q['W_in_x'], s = q_rows(L['W_in_x'])
    Q['rq_in_x'] = rq_for(s, 'in_x')
    cw, s = q_rows(np.stack([L['conv_w0'], L['conv_w1']], -1))         # one scale per channel
    Q['conv_w0'], Q['conv_w1'] = cw[:, 0], cw[:, 1]
    Q['rq_conv'] = rq_for(s, 'conv')
    Q['cb'] = q_fixed(L['cb'], PARAM['CB'])
    Q['W_x'], s = q_rows(L['W_x'])
    R = Q['W_x'].shape[0] // 3
    Q['rq_x'] = np.concatenate([rq_for(s[:R], 'dl'), rq_for(s[R:2 * R], 'b'), rq_for(s[2 * R:], 'c')])
    Q['b_dt'] = q_fixed(L['b_dt'], PARAM['B_DT'])
    Q['W_dt'], s = q_rows(L['W_dt'])
    Q['rq_dt'] = rq_for(s, 'dt')
    Q['A2'] = q_fixed(np.clip(L['A2'], A2_LO, A2_HI), PARAM['A2'])
    Q['D'] = q_fixed(L['D'], PARAM['D'])
    Q['W_in_z'], s = q_rows(L['W_in_z'])
    Q['rq_z'] = rq_for(s, 'z')
    Q['W_out'], s = q_rows(L['W_out'])
    Q['rq_out'] = rq_for(s, 'out')
    return Q


def quantise(Pf, cfg):
    """Folded float64 parameters -> integer parameter set (asserts spec 3.2 ranges)."""
    E_out, s = q_rows(Pf['E_out'])
    P = {'E_in': q_fixed(Pf['E_in'], PARAM['E_IN']), 'E_out': E_out, 'rq_logits': rq_for(s, 'logits'),
         'layers': [quantise_layer(L) for L in Pf['layers']]}
    check_ranges(P, cfg)
    return P


def load_float_params(ckpt):
    """.pt checkpoint -> (cfg, folded float64 parameters)."""
    import torch
    ck = torch.load(ckpt, map_location='cpu')
    return ck['config'], fold_checkpoint({k: v.double().numpy() for k, v in ck['model'].items()},
                                         ck['config'])


def export(ckpt, out):
    cfg, Pf = load_float_params(ckpt)
    P = quantise(Pf, cfg)
    save_params(out, P, cfg)
    return cfg, P


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('ckpt')
    ap.add_argument('out')
    a = ap.parse_args()
    cfg, P = export(a.ckpt, a.out)
    sats = sum(int(np.sum(np.abs(L[k]) == PARAM[f].hi)) for L in P['layers']
               for k, f in (('cb', 'CB'), ('b_dt', 'B_DT'), ('D', 'D')))
    print(f'wrote {a.out}: {cfg}; fixed-format saturations: {sats}')


if __name__ == '__main__':
    main()
