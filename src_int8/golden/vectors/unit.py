"""Unit vectors for the datapath units (lane, writeback, NLU), bit-exact from the golden ops.

  lane.hex  "k ps a[0..k-1] b[0..k-1] acc": random dots K in 1..128 with ps, INT24 x INT16 operands
            (one record per line; a and b as 6- and 4-digit hex lists; acc 8 digits)
  wb.hex    "mode acc M s sh addend w out": mode 0 = sh (wb_sh + addend), 1 = rq (wb_rq + addend)
  nlu.hex   "fn x i f shfn zero y": every input of the uniform tables (fn 0, 1), boundary and
            random exp2 (fn 2) and rsqrt (fn 3) inputs
"""
import numpy as np

from ..ops.lane import dot, rq, sh
from ..ops.nlu import ADDR, EXP2, FUNCS, RSQRT, lut
from .common import hex_lines


def lane_vectors(path, rng, n=2000):
    rows = []
    for _ in range(n):
        k = int(rng.integers(1, 129))
        ps = int(rng.choice([0, 0, 0, 4, 6, 11, 15]))
        a = rng.integers(-(1 << 23), 1 << 23, k) if ps else rng.integers(-128, 128, k)
        b = rng.integers(-32768, 32768, k) if ps else rng.integers(-128, 128, k)
        while (k * int(np.abs(a).max()) * int(np.abs(b).max())) >> ps >= 1 << 31:
            a = a >> 1                                              # keep the sum below 2^31 (spec 5)
        acc = dot(a[None], b, ps)[0]
        rows.append(f'{k:02x} {ps:x} ' + ' '.join(f'{int(v) & 0xFFFFFF:06x}' for v in a) + ' '
                    + ' '.join(f'{int(v) & 0xFFFF:04x}' for v in b) + f' {int(acc) & 0xFFFFFFFF:08x}\n')
    with open(path, 'w') as f:
        f.writelines(rows)
    return n


def wb_vectors(path, rng, n=20000):
    acc = rng.integers(-(1 << 31), 1 << 31, n)
    acc[:64] = [0, 1, -1, (1 << 31) - 1, -(1 << 31), 127, 128, -128, -129, 32767, 32768, -32768, -32769,
                (1 << 23) - 1, 1 << 23, -(1 << 23), -(1 << 23) - 1] + [1 << k for k in range(31)] + [-(1 << k) for k in range(16)]
    M = rng.integers(1 << 14, 1 << 15, n)
    s = rng.integers(1, 48, n)
    shift = rng.integers(0, 32, n)
    addend = rng.integers(-32768, 32768, n) * rng.integers(0, 2, n)
    w = rng.choice([8, 16, 24], n)
    mode = rng.integers(0, 2, n)
    out = np.empty(n, np.int64)
    for i in range(n):
        if mode[i]:
            out[i] = rq(np.array([acc[i]]), np.array([[M[i], s[i]]]), int(w[i]), addend[i])[0]
        else:
            out[i] = sh(np.array([acc[i]]), int(shift[i]), int(w[i]), addend[i])[0]
    return hex_lines(path, [(mode, 1), (acc, 8), (M, 4), (s, 2), (shift, 2), (addend, 4), (w, 2), (out, 8)])


def nlu_vectors(path, rng):
    cols = {c: [] for c in ('fn', 'x', 'i', 'f', 'shfn', 'zero', 'y')}
    q = 1 << 19
    inputs = {
        0: np.arange(-2200, 2200), 1: np.arange(-2200, 2200),
        2: np.concatenate([[0, -1, -2, -q + 1, -q, -q - 1, -15 * q, -16 * q + 1, -16 * q, -16 * q - 1, -(1 << 31), 5, 1 << 20],
                           -rng.integers(1, 16 * q, 20000)]),
        3: np.concatenate([[16, 17, 31, 32, 63, 64, (1 << 16) - 1, 1 << 16, (1 << 17) - 1, 1 << 17, (1 << 18) - 1, 1 << 18, (1 << 31) - 1],
                           rng.integers(16, 1 << 31, 20000), 16 << rng.integers(0, 27, 2000)]),
    }
    for code, fn in enumerate(FUNCS):
        x = inputs[code].astype(np.int64)
        i, f, s, z = ADDR[fn](x)
        for c, v in (('fn', np.full(len(x), code)), ('x', x), ('i', fn.base + i), ('f', f), ('shfn', s),
                     ('zero', z), ('y', lut(fn, x))):
            cols[c].append(v)
    flat = [np.concatenate(cols[c]) for c in cols]
    return hex_lines(path, list(zip(flat, (1, 8, 3, 3, 2, 1, 4))))


def generate(out_dir, seed=0):
    rng = np.random.default_rng(seed)
    return {'lane': lane_vectors(out_dir / 'lane.hex', rng), 'wb': wb_vectors(out_dir / 'wb.hex', rng),
            'nlu': nlu_vectors(out_dir / 'nlu.hex', rng)}


assert EXP2 is FUNCS[2] and RSQRT is FUNCS[3]
