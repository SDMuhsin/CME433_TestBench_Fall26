"""Shared helpers for vector files: fixed-width two's-complement hex, one record per line."""
from pathlib import Path

import numpy as np


def hex_lines(path, cols):
    """cols = [(int array, hex digits), ...] -> space-separated hex per record; returns count."""
    fmt = ' '.join(f'%0{w}x' for _, w in cols) + '\n'
    data = [np.asarray(c).astype(np.int64).reshape(-1) & ((1 << (4 * w)) - 1) for c, w in cols]
    with open(Path(path), 'w') as f:
        for row in zip(*data):
            f.write(fmt % row)
    return len(data[0])


def write_memh(path, values, digits):
    """One value per line (two's complement, `digits` hex digits)."""
    v = np.asarray(values).astype(np.int64).reshape(-1) & ((1 << (4 * digits)) - 1)
    Path(path).write_text(''.join(f'{int(x):0{digits}x}\n' for x in v))
    return len(v)
