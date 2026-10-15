"""mb_nlu vectors, exhaustive: every canonical FP16 x for each function (rsqrt: x > 0).

"fn x idx q scale byp y": idx = ROM word of the left grid point, q = f * 2^11, scale = output
scale (exp2 clamped to -128 as in hardware; bit-exact, see mb_fp32_wb), y = golden lut(fn, x).
"""
import numpy as np

from src.golden.arith.nlu import FUNCS, RSQRT, SOFTPLUS, address, lut

from .common import legal16, value, write_hex


def nlu_vectors(path):
    cols = {c: [] for c in ('fn', 'x', 'idx', 'q', 'scale', 'byp', 'y')}
    allx = legal16()
    for code, fn in enumerate(FUNCS):
        x = allx[value(allx) > 0] if fn is RSQRT else allx
        i, f, _, s = address(fn, x)
        byp = (fn is SOFTPLUS) & (value(x) >= fn.hi)
        for c, v in (('fn', np.full(len(x), code)), ('x', x), ('idx', fn.base + i),
                     ('q', (value(f) * 2048).astype(np.int64)), ('scale', np.maximum(s, -128)),
                     ('byp', byp), ('y', lut(fn, x))):
            cols[c].append(v)
    flat = [np.concatenate(cols[c]) for c in cols]
    return write_hex(path, list(zip(flat, (1, 4, 3, 3, 2, 1, 4))))


def generate(out):
    return {'nlu': nlu_vectors(out / 'nlu.hex')}
