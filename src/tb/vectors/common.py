"""Shared helpers for unit-test vector generation (golden = src/golden, bit-exact)."""
from pathlib import Path

import numpy as np

from src.golden.arith.fp import canon16, to_fp16, value

F32, U16, U32 = np.float32, np.uint16, np.uint32


def rng(seed):
    return np.random.default_rng(seed)


def f32bits(v):
    return np.asarray(v, dtype=F32).view(U32)


def legal16():
    """All canonical FP16 codes (no subnormal, Inf/NaN or -0)."""
    b = np.arange(65536, dtype=U32).astype(U16)
    return b[canon16(b) == b]


def rand16(r, n):
    """n random canonical FP16 codes, uniform over the legal codes (all exponents)."""
    return r.choice(legal16(), n)


def real16(r, n, decades=2.0):
    """n canonical FP16 codes with a 'realistic' spread: N(0,1) * 10^U(-decades, decades)."""
    return to_fp16(r.standard_normal(n) * 10.0 ** r.uniform(-decades, decades, n))


def write_hex(path, cols):
    """One line per vector; cols = [(int array, hex digits), ...] -> space-separated hex."""
    fmt = ' '.join(f'%0{w}x' for _, w in cols) + '\n'
    data = [np.asarray(c).astype(np.int64) & ((1 << (4 * w)) - 1) for c, w in cols]
    with open(Path(path), 'w') as f:
        for row in zip(*data):
            f.write(fmt % row)
    return len(data[0])


__all__ = ['F32', 'U16', 'U32', 'rng', 'f32bits', 'legal16', 'rand16', 'real16', 'write_hex',
           'canon16', 'value']
