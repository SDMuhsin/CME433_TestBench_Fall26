"""Spec section 7: the per-token host weight stream (bytes, little endian) and its inverse.

  EMB     E_in[token, 0..63]                                     64 x INT16
  per block:
    IN_X   for d: W_in_x[d, :], RQ, w0[d], w1[d], RQ_conv, cb[d]  74 B/row
    X_PROJ for j: W_x[j, :], RQ                                   99 B/row
    CHAN   for d: b_dt[d], W_dt[d, :], RQ_dt, A'[d, :], D[d], W_in_z[d, :], RQ_z   85 B/row
    OUT    for i: W_out[i, :], RQ                                 99 B/row
  LOGITS  for v: E_out[v, :], RQ                                  67 B/row
RQ = M low byte, M high byte, s.  Total 54,280 B for the e96 configuration.
"""
import numpy as np

from .params import LAYER_KEYS

U8 = np.uint8


def i8(a):
    """INT8 values -> bytes (two's complement)."""
    return (np.asarray(a, dtype=np.int64) & 0xFF).astype(U8).reshape(-1)


def i16(a):
    """INT16 values -> little-endian byte pairs."""
    v = np.asarray(a, dtype=np.int64) & 0xFFFF
    return np.stack([v & 0xFF, v >> 8], -1).astype(U8).reshape(-1)


def rq_bytes(rq):
    """(M, s) pairs [..., 2] -> 3 bytes each."""
    rq = np.asarray(rq, dtype=np.int64)
    M, s = rq[..., 0], rq[..., 1]
    return np.stack([M & 0xFF, M >> 8, s], -1).astype(U8).reshape(-1)


def _rows(*cols):
    """Interleave per-row byte columns [rows, k_i] into one row-major byte array."""
    return np.concatenate([np.asarray(c, dtype=U8) for c in cols], -1).reshape(-1)


def _col(fn, a, rows):
    return fn(a).reshape(rows, -1)


def layer_sections(L):
    """-> list of the four byte arrays IN_X, X_PROJ, CHAN, OUT of one block."""
    E, J, D = L['W_in_x'].shape[0], L['W_x'].shape[0], L['W_out'].shape[0]
    in_x = _rows(_col(i8, L['W_in_x'], E), _col(rq_bytes, L['rq_in_x'], E), _col(i8, L['conv_w0'], E),
                 _col(i8, L['conv_w1'], E), _col(rq_bytes, L['rq_conv'], E), _col(i16, L['cb'], E))
    x_proj = _rows(_col(i8, L['W_x'], J), _col(rq_bytes, L['rq_x'], J))
    chan = _rows(_col(i16, L['b_dt'], E), _col(i8, L['W_dt'], E), _col(rq_bytes, L['rq_dt'], E),
                 _col(i16, L['A2'], E), _col(i8, L['D'], E), _col(i8, L['W_in_z'], E),
                 _col(rq_bytes, L['rq_z'], E))
    out = _rows(_col(i8, L['W_out'], D), _col(rq_bytes, L['rq_out'], D))
    return [in_x, x_proj, chan, out]


def token_stream(P, token):
    """Full byte stream for one token (uint8 array of stream_bytes(cfg))."""
    parts = [i16(P['E_in'][token])]
    for L in P['layers']:
        parts += layer_sections(L)
    V = P['E_out'].shape[0]
    parts.append(_rows(_col(i8, P['E_out'], V), _col(rq_bytes, P['rq_logits'], V)))
    return np.concatenate(parts)


def row_bytes(cfg):
    """Bytes per row of (IN_X, X_PROJ, CHAN, OUT, LOGITS)."""
    D, E, R, N = cfg['d_model'], cfg['d_inner'], cfg['dt_rank'], cfg['d_state']
    return D + 3 + 1 + 1 + 3 + 2, E + 3, 2 + R + 3 + 2 * N + 1 + D + 3, E + 3, D + 3


def stream_bytes(cfg):
    D, E, V, R, N = cfg['d_model'], cfg['d_inner'], cfg['vocab'], cfg['dt_rank'], cfg['d_state']
    in_x, x_proj, chan, out, logit = row_bytes(cfg)
    return 2 * D + cfg['n_layer'] * (E * in_x + (R + 2 * N) * x_proj + E * chan + D * out) + V * logit


def state_safe_bytes(cfg):
    """Stream bytes consumed before the first CONV0 write: through w1[0] (spec 8: 197 B)."""
    return 2 * cfg['d_model'] + cfg['d_model'] + 3 + 1 + 1


class _Reader:
    def __init__(self, b):
        self.b, self.pos = np.asarray(b, dtype=np.int64), 0

    def take(self, n):
        v = self.b[self.pos:self.pos + n]
        self.pos += n
        return v

    def s8(self, n=1):
        v = self.take(n)
        return np.where(v >= 128, v - 256, v)

    def s16(self, n=1):
        v = self.take(2 * n).reshape(n, 2)
        v = v[:, 0] | (v[:, 1] << 8)
        return np.where(v >= 32768, v - 65536, v)

    def rq(self, n=1):
        v = self.take(3 * n).reshape(n, 3)
        return np.stack([v[:, 0] | (v[:, 1] << 8), v[:, 2]], -1)


def unpack_stream(stream, cfg):
    """Inverse of token_stream: bytes -> (embedding row INT16 [D], params without E_in)."""
    D, E, V, R, N = cfg['d_model'], cfg['d_inner'], cfg['vocab'], cfg['dt_rank'], cfg['d_state']
    rd = _Reader(stream)
    assert len(rd.b) == stream_bytes(cfg), 'stream length mismatch'
    emb = rd.s16(D)
    layers = []
    for _ in range(cfg['n_layer']):
        L = {k: [] for k in LAYER_KEYS}
        for _ in range(E):
            L['W_in_x'].append(rd.s8(D)); L['rq_in_x'].append(rd.rq()[0])
            L['conv_w0'].append(rd.s8()[0]); L['conv_w1'].append(rd.s8()[0])
            L['rq_conv'].append(rd.rq()[0]); L['cb'].append(rd.s16()[0])
        for _ in range(R + 2 * N):
            L['W_x'].append(rd.s8(E)); L['rq_x'].append(rd.rq()[0])
        for _ in range(E):
            L['b_dt'].append(rd.s16()[0]); L['W_dt'].append(rd.s8(R)); L['rq_dt'].append(rd.rq()[0])
            L['A2'].append(rd.s16(N)); L['D'].append(rd.s8()[0])
            L['W_in_z'].append(rd.s8(D)); L['rq_z'].append(rd.rq()[0])
        for _ in range(D):
            L['W_out'].append(rd.s8(E)); L['rq_out'].append(rd.rq()[0])
        layers.append({k: np.array(v, dtype=np.int64) for k, v in L.items()})
    E_out, rq_logits = [], []
    for _ in range(V):
        E_out.append(rd.s8(D)); rq_logits.append(rd.rq()[0])
    assert rd.pos == len(rd.b)
    return emb, {'E_out': np.array(E_out, dtype=np.int64), 'rq_logits': np.array(rq_logits, dtype=np.int64),
                 'layers': layers}
