"""Error metrics of a multiplier over all (a, b) operand pairs, or over uniform random pairs,
in parallel chunks.

unsigned_stats(builder, n): a, b in [0, 2^n); 2^32 pairs for n = 16 (a few minutes on many
cores). signed_stats(builder, n): a, b in [-2^(n-1), 2^(n-1)); `samples` > 0 draws that many
uniform random pairs instead (fixed seed). `builder` is a module-level callable returning a
mult.Multiplier (rebuilt per worker); NMED is normalised by `max_out`.
"""
from multiprocessing import Pool

import numpy as np

from .metrics import ErrorStats

_M = None


def _init(builder, args):
    global _M
    _M = builder(*args)


def _chunk(job):
    lo, a0, a1, n, seed, size = job
    if seed is None:
        b = np.arange(lo, lo + (1 << n), dtype=np.int64)
        a = np.repeat(np.arange(a0, a1, dtype=np.int64), b.size)
        b = np.tile(b, a1 - a0)
    else:
        rng = np.random.default_rng(seed)
        a = rng.integers(lo, lo + (1 << n), size, dtype=np.int64)
        b = rng.integers(lo, lo + (1 << n), size, dtype=np.int64)
    return ErrorStats(1).add(_M.products(a, b), a * b)


def _run(builder, args, jobs, work, max_out):
    total = ErrorStats(max_out)
    with Pool(jobs, initializer=_init, initargs=(builder, args)) as pool:
        for st in pool.imap_unordered(_chunk, work):
            total.merge(st)
    return total


def _exhaustive(builder, n, lo, args, jobs, rows, max_out):
    rows = rows or max(1, (1 << 22) >> n)          # a values per chunk (~4M products)
    work = [(lo, a0, min(a0 + rows, lo + (1 << n)), n, None, 0)
            for a0 in range(lo, lo + (1 << n), rows)]
    return _run(builder, args, jobs, work, max_out)


def unsigned_stats(builder, n, args=(), jobs=32, rows=None):
    return _exhaustive(builder, n, 0, args, jobs, rows, ((1 << n) - 1) ** 2).result(2 * n)


def signed_stats(builder, n, args=(), jobs=32, samples=0, max_out=None, chunk=1 << 22):
    lo = -(1 << (n - 1))
    max_out = max_out or 1 << (2 * n - 2)
    if not samples:
        return _exhaustive(builder, n, lo, args, jobs, None, max_out).result(2 * n)
    work = [(lo, 0, 0, n, 1000 + k, min(chunk, samples - k * chunk))
            for k in range(-(-samples // chunk))]
    return _run(builder, args, jobs, work, max_out).result(2 * n)
