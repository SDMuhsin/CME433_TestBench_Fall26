"""Exhaustive error metrics of a multiplier over all (a, b) operand pairs, in parallel chunks.

unsigned_stats(builder, n): a, b in [0, 2^n); 2^32 pairs for n = 16 (a few minutes on many
cores). `builder` is a module-level callable returning a mult.Multiplier (rebuilt per worker).
"""
from multiprocessing import Pool

import numpy as np

from .metrics import ErrorStats

_M = None


def _init(builder, args):
    global _M
    _M = builder(*args)


def _chunk(job):
    a0, a1, n = job
    b = np.arange(1 << n, dtype=np.int64)
    a = np.repeat(np.arange(a0, a1, dtype=np.int64), b.size)
    b = np.tile(b, a1 - a0)
    exact = a * b
    st = ErrorStats(1).add(_M.products(a, b), exact)
    return st


def unsigned_stats(builder, n, args=(), jobs=32, rows=None):
    rows = rows or max(1, (1 << 22) >> n)          # a values per chunk (~4M products)
    total = ErrorStats(((1 << n) - 1) ** 2)
    work = [(a0, min(a0 + rows, 1 << n), n) for a0 in range(0, 1 << n, rows)]
    with Pool(jobs, initializer=_init, initargs=(builder, args)) as pool:
        for st in pool.imap_unordered(_chunk, work):
            for k in ('n', 'nz', 'err', 'zero_hits', 'sum_abs', 'sum_e', 'sum_red'):
                setattr(total, k, getattr(total, k) + getattr(st, k))
            total.max_abs = max(total.max_abs, st.max_abs)
    return total.result()
