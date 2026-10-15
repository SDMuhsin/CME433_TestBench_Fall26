"""Trained checkpoint -> hardware FP16 parameter set (.npz of uint16 bit patterns).

Export transforms (host side, float64 then one RNE to FP16):
  * block RMSNorm gain g folded into in_proj columns: W_in' = W_in * g
  * final RMSNorm gain folded into the output embedding: E_out = E * g_f (input stays E_in = E)
  * A' = -exp(A_log) * log2(e), so dA = exp2(dt * A')
"""
import argparse
import json

import numpy as np

from ..arith.fp import canon16, to_fp16

LAYER_KEYS = ('W_in_x', 'W_in_z', 'conv_b', 'conv_w0', 'conv_w1', 'W_x', 'W_dt', 'b_dt', 'A2', 'D',
              'W_out')


def fold_checkpoint(state, cfg):
    """Float state dict (numpy float64) -> dict of float64 hardware tensors."""
    E = cfg['d_inner']
    emb = state['embed.weight']
    P = {'E_in': emb, 'E_out': emb * state['norm_f.weight'][None, :]}
    for l in range(cfg['n_layer']):
        s = {k[len(f'blocks.{l}.'):]: v for k, v in state.items() if k.startswith(f'blocks.{l}.')}
        W_in = s['in_proj.weight'] * s['norm.weight'][None, :]
        layer = {'W_in_x': W_in[:E], 'W_in_z': W_in[E:], 'conv_b': s['conv_b'],
                 'conv_w0': s['conv_w'][:, 0], 'conv_w1': s['conv_w'][:, 1], 'W_x': s['x_proj.weight'],
                 'W_dt': s['dt_proj.weight'], 'b_dt': s['dt_proj.bias'],
                 'A2': -np.exp(s['A_log']) * np.log2(np.e), 'D': s['D'], 'W_out': s['out_proj.weight']}
        P.update({f'{k}.{l}': v for k, v in layer.items()})
    return P


def save_params(path, P16, cfg):
    np.savez(path, config=json.dumps(cfg), **P16)


def load_params(path):
    """-> (cfg dict, {'E_in', 'E_out', 'layers': [ {key: uint16 array} ]})."""
    z = np.load(path)
    cfg = json.loads(str(z['config']))
    for k in z.files:
        if k != 'config':
            assert np.array_equal(canon16(z[k]), z[k]), f'non-canonical FP16 in {k}'
    layers = [{k: z[f'{k}.{l}'] for k in LAYER_KEYS} for l in range(cfg['n_layer'])]
    return cfg, {'E_in': z['E_in'], 'E_out': z['E_out'], 'layers': layers}


def main():
    import torch
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('ckpt')
    ap.add_argument('out')
    a = ap.parse_args()
    ck = torch.load(a.ckpt, map_location='cpu')
    state = {k: v.double().numpy() for k, v in ck['model'].items()}
    P = fold_checkpoint(state, ck['config'])
    P16 = {k: to_fp16(v) for k, v in P.items()}
    for k, v in P.items():
        flushed = int(np.sum((v != 0) & (P16[k] == 0)))
        if flushed or np.abs(v).max() > 65504:
            print(f'{k}: {flushed} flushed to zero, max |w| {np.abs(v).max():.3g}')
    save_params(a.out, P16, ck['config'])


if __name__ == '__main__':
    main()
