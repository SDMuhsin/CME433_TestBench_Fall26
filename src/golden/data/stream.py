"""Per-token host weight stream (16-bit FP16 words, consumption order of the sequencer).

  EMB      E_in[token, 0..63]
  per layer l:
    IN_X   for d < E:  W_in_x[d, 0..63], conv_b[d], conv_w0[d], conv_w1[d]
    X_PROJ for j < R+2N: W_x[j, 0..E-1]                 (j: dt_low | B | C)
    CHAN   for d < E:  b_dt[d], W_dt[d, 0..R-1], A2[d, 0..N-1], D[d], W_in_z[d, 0..63]
    OUT    for i < 64: W_out[i, 0..E-1]
  LOGITS   for v < 128: E_out[v, 0..63]
"""
import numpy as np


def _col(v):
    return v[:, None]


def _sections(L):
    """Per-layer sections as 2-D arrays whose rows are streamed in order."""
    in_x = np.hstack([L['W_in_x'], _col(L['conv_b']), _col(L['conv_w0']), _col(L['conv_w1'])])
    chan = np.hstack([_col(L['b_dt']), L['W_dt'], L['A2'], _col(L['D']), L['W_in_z']])
    return in_x, L['W_x'], chan, L['W_out']


def token_stream(P, token):
    """Full word stream for one token (uint16 array)."""
    parts = [P['E_in'][token]]
    for L in P['layers']:
        parts += [s.reshape(-1) for s in _sections(L)]
    parts.append(P['E_out'].reshape(-1))
    return np.concatenate(parts).astype(np.uint16)


def stream_words(cfg):
    """Words per token."""
    D, E, V = cfg['d_model'], cfg['d_inner'], cfg['vocab']
    R, N = cfg['dt_rank'], cfg['d_state']
    per_layer = E * (D + 3) + (R + 2 * N) * E + E * (1 + R + N + 1 + D) + D * E
    return D + cfg['n_layer'] * per_layer + V * D


def unpack_stream(words, cfg):
    """Inverse of token_stream: -> (embedding row, params without E_in)."""
    D, E, V = cfg['d_model'], cfg['d_inner'], cfg['vocab']
    R, N = cfg['dt_rank'], cfg['d_state']
    pos = 0

    def take(rows, cols):
        nonlocal pos
        block = words[pos:pos + rows * cols].reshape(rows, cols)
        pos += rows * cols
        return block

    emb = take(1, D)[0]
    layers = []
    for _ in range(cfg['n_layer']):
        in_x, wx, chan, wout = take(E, D + 3), take(R + 2 * N, E), take(E, 1 + R + N + 1 + D), take(D, E)
        layers.append({'W_in_x': in_x[:, :D], 'conv_b': in_x[:, D], 'conv_w0': in_x[:, D + 1],
                       'conv_w1': in_x[:, D + 2], 'W_x': wx, 'b_dt': chan[:, 0],
                       'W_dt': chan[:, 1:1 + R], 'A2': chan[:, 1 + R:1 + R + N], 'D': chan[:, 1 + R + N],
                       'W_in_z': chan[:, 2 + R + N:], 'W_out': wout})
    E_out = take(V, D)
    assert pos == len(words), 'stream length mismatch'
    return emb, {'E_out': E_out, 'layers': layers}
