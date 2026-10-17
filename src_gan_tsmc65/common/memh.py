"""Hex memory-file I/O: one two's-complement hex word per line ($readmemh format)."""
from pathlib import Path

import numpy as np


def read_memh(path, bits=8, signed=True):
    """-> int64 array of the words in `path` (comments '//' and blank lines skipped)."""
    words = []
    for line in Path(path).read_text().splitlines():
        line = line.split('//', 1)[0].strip()
        if line:
            words.extend(int(w, 16) for w in line.split())
    v = np.array(words, np.int64)
    if signed:
        v = np.where(v >= 1 << (bits - 1), v - (1 << bits), v)
    return v


def write_memh(path, values, bits=8):
    """Write `values` (any int array) as `bits`-wide two's-complement hex, one per line."""
    mask, width = (1 << bits) - 1, (bits + 3) // 4
    Path(path).write_text(''.join(f'{int(v) & mask:0{width}x}\n' for v in np.ravel(values)))
