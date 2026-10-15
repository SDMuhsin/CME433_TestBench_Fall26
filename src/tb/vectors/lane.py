"""mb_lane vectors: one line per lane step, "first a b init scale acc y".

acc = expected FP32 accumulator after the step (golden fp.mac, base = init on the first step),
y = writeback(acc, scale).  Op shapes as used by spec section 5: GEMV rows (K up to 128, with
and without init), MUL, scan MADD2 (dA*h + dtu*B), conv (cb + w0*prev + w1*xi).  Operands are
half realistic values, half random codes over all exponents.
"""
import numpy as np

from src.golden.arith.fp import mac, to_fp16, value, writeback

from .common import F32, f32bits, rand16, real16, rng, write_hex


def _operands(r, shape, realistic):
    n = int(np.prod(shape))
    return (real16(r, n) if realistic else rand16(r, n)).reshape(shape)


def _rows(r, rows, k, with_init, realistic, a=None):
    """Batch of `rows` accumulations of length k -> dict of [rows, k] step arrays."""
    a = _operands(r, (rows, k), realistic) if a is None else a
    b = _operands(r, (rows, k), realistic)
    init = _operands(r, (rows,), realistic) if with_init else np.zeros(rows, np.uint16)
    scale = np.where(r.random(rows) < 0.85, 0,
                     np.where(r.random(rows) < 0.7, r.integers(-8, 9, rows), r.integers(-128, 128, rows)))
    acc = value(init).astype(F32)
    accs, ys = np.zeros((rows, k), np.uint32), np.zeros((rows, k), np.uint16)
    for j in range(k):
        acc = mac(acc, a[:, j], b[:, j])
        accs[:, j], ys[:, j] = f32bits(acc), writeback(acc, scale)
    first = np.zeros((rows, k), np.int64)
    first[:, 0] = 1
    rep = lambda v: np.repeat(np.asarray(v)[:, None], k, axis=1)
    return dict(first=first, a=a, b=b, init=rep(init), scale=rep(scale), acc=accs, y=ys)


def _scan_rows(r, rows):
    """h' = dA*h + dtu*B with dA in (0, 1]: the scan's MADD2 shape."""
    da = np.maximum(to_fp16(r.uniform(0, 1, rows)), 0x0400)
    a = np.stack([da, real16(r, rows)], axis=1)
    return _rows(r, rows, 2, False, True, a=a)


def lane_vectors(path):
    r = rng(3)
    batches = [_scan_rows(r, 20000)]
    for realistic in (True, False):
        batches += [_rows(r, 20000, 1, False, realistic),                  # MUL
                    _rows(r, 10000, 2, True, realistic)]                   # conv MADD2
        for k, rows in ((3, 3000), (4, 3000), (12, 2000), (64, 800), (96, 800), (128, 200)):
            batches += [_rows(r, rows, k, False, realistic), _rows(r, rows, k, True, realistic)]
    cols = ['first', 'a', 'b', 'init', 'scale', 'acc', 'y']
    flat = {c: np.concatenate([bt[c].ravel() for bt in batches]) for c in cols}
    return write_hex(path, [(flat[c], w) for c, w in zip(cols, (1, 4, 4, 4, 2, 8, 4))])


def generate(out):
    return {'lane': lane_vectors(out / 'lane.hex')}
