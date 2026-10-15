"""Unit-test vectors from the spec-formula reference: python3 -m src_int8.tb.ref.vectors <out_dir>.

One hex line per vector (columns documented per generator).  Random cases plus the corner
cases of each unit: rounding ties of both signs, saturation at every width, maximum operand
magnitudes, every input of the uniform LUT grids, exp2 / rsqrt boundaries and the zero flag.
"""
import random
import sys
from pathlib import Path

from . import nlu_ref as nlu
from .intmath import mac, rsh, sat, wb_rq, wb_sh

MASK = lambda v, bits: v & ((1 << bits) - 1)


def _write(path, rows, widths):
    fmt = ' '.join(f'%0{w}x' for w in widths) + '\n'
    with open(path, 'w') as f:
        for row in rows:
            f.write(fmt % tuple(MASK(v, 4 * w) for v, w in zip(row, widths)))
    return len(rows)


def _rnd_signed(r, bits):
    return r.randrange(-(1 << (bits - 1)), 1 << (bits - 1))


# ---------------------------------------------------------------- mq_rsh (40 -> 32, k 0..15)
def rsh_vectors(path, r):
    rows = []
    for _ in range(20000):
        k = r.randrange(16)
        v = _rnd_signed(r, 40) >> r.randrange(0, 12)
        if abs(rsh(v, k)) >= 1 << 31:
            v >>= 9
        rows.append((v, k, rsh(v, k)))
    for k in range(16):                                    # ties of both signs, max magnitudes
        for base in (0, 1, -1, 5, -5, (1 << 30) - 1, -(1 << 30)):
            v = (base << k) + ((1 << (k - 1)) if k else 0)
            for dv in (-1, 0, 1):
                if -(1 << 39) <= v + dv < (1 << 39):
                    rows.append((v + dv, k, rsh(v + dv, k)))
    return _write(path, rows, (10, 1, 8))


# ---------------------------------------------------------------- mq_sat (50 -> 8/16/24/32)
def sat_vectors(path, r):
    rows = []
    for _ in range(20000):
        ww = r.randrange(4)
        v = _rnd_signed(r, r.choice((8, 9, 16, 17, 24, 25, 33, 50)))
        rows.append((v, ww, sat(v, (8, 16, 24, 32)[ww])))
    for ww, w in enumerate((8, 16, 24)):
        for v in (-(1 << (w - 1)) - 1, -(1 << (w - 1)), (1 << (w - 1)) - 1, 1 << (w - 1), 0, -1,
                  (1 << 49) - 1, -(1 << 49)):
            rows.append((v, ww, sat(v, w)))
    return _write(path, rows, (13, 1, 8))


# ---------------------------------------------------------------- mq_lane: "first a b init ps acc"
def _dot(r, rows, k, a_bits, b_bits, ps, init=0):
    out = []
    for _ in range(rows):
        acc = init
        for j in range(k):
            a, b = _rnd_signed(r, a_bits), _rnd_signed(r, b_bits)
            acc = mac(acc, a, b, ps)
            out.append((1 if j == 0 else 0, a, b, init, ps, acc))
    return out


def lane_vectors(path, r):
    rows = []
    rows += _dot(r, 300, 64, 8, 8, 0)                          # GEMV rows (stream x activation)
    rows += _dot(r, 200, 96, 8, 8, 0)
    rows += _dot(r, 100, 128, 8, 8, 0)
    rows += _dot(r, 2000, 1, 16, 16, 0)                        # element-wise products
    rows += _dot(r, 1000, 64, 16, 16, 6, init=16)              # RMSNorm mean square
    for ps in range(16):                                       # all product shifts, 2-step MADD
        rows += _dot(r, 300, 2, 24 if ps >= 9 else 16, 16, ps)  # (24 x 16 needs ps >= 9 to fit)
    rows += _dot(r, 1000, 5, 24, 8, 11)                        # y dot (H x C, ps 11)
    rows += _dot(r, 1000, 2, 16, 12, 0)                        # LERP shape
    # corners: max magnitudes, ties at the product shift
    for a, b, ps in ((-(1 << 23), -(1 << 15), 15), ((1 << 23) - 1, -(1 << 15), 15),
                     (-(1 << 23), (1 << 15) - 1, 15), ((1 << 23) - 1, (1 << 15) - 1, 15),
                     (-32768, -32768, 6), (32767, 32767, 6), (1 << 11, 1, 12), (-(1 << 11), 1, 12),
                     (3 << 10, 1, 12), (-(3 << 10), 1, 12)):
        rows.append((1, a, b, 0, ps, mac(0, a, b, ps)))
    return _write(path, rows, (1, 6, 4, 8, 1, 8))


# ---------------------------------------------------------------- mq_wb: "acc mode sh m s addend ww y"
def _wb(acc, mode, sh, M, s, addend, ww):
    v = wb_rq(acc, M, s) if mode & 1 else wb_sh(acc, sh)
    if mode & 2:
        v += addend
    return sat(v, (8, 16, 24, 32)[ww])


def wb_vectors(path, r):
    rows = []
    for _ in range(60000):
        mode, ww = r.randrange(4), r.randrange(4)
        if mode & 1 and ww == 3:
            ww = r.randrange(3)
        acc = _rnd_signed(r, 32) >> r.randrange(0, 24)
        sh, M, s = r.randrange(32), r.randrange(1 << 14, 1 << 15), r.randrange(1, 48)
        addend = _rnd_signed(r, 16)
        rows.append((acc, mode, sh, M, s, addend, ww, _wb(acc, mode, sh, M, s, addend, ww)))
    # corners: ties, saturation at each width, s / M bounds, raw pass-through
    for acc in (0, 1, -1, (1 << 31) - 1, -(1 << 31), 127, 128, -128, -129, 32767, 32768, -32768,
                -32769, (1 << 23) - 1, 1 << 23, -(1 << 23), -(1 << 23) - 1):
        for ww in range(4):
            rows.append((acc, 0, 0, 1 << 14, 1, 0, ww, _wb(acc, 0, 0, 1 << 14, 1, 0, ww)))
        for sh in (1, 5, 12, 19, 31):
            for dv in (-1, 0, 1):
                a = (acc >> sh << sh) + (1 << (sh - 1)) + dv
                if -(1 << 31) <= a < (1 << 31):
                    rows.append((a, 0, sh, 1 << 14, 1, 0, 1, _wb(a, 0, sh, 1 << 14, 1, 0, 1)))
        for M, s in (((1 << 14), 1), ((1 << 15) - 1, 47), ((1 << 14), 47), ((1 << 15) - 1, 1),
                     (0x6000, 24)):
            for ww in range(3):
                rows.append((acc, 1, 0, M, s, 0, ww, _wb(acc, 1, 0, M, s, 0, ww)))
                rows.append((acc, 3, 0, M, s, 32767, ww, _wb(acc, 3, 0, M, s, 32767, ww)))
                rows.append((acc, 3, 0, M, s, -32768, ww, _wb(acc, 3, 0, M, s, -32768, ww)))
    for acc in (3, -3, 5, -5, 0x8000, -0x8000):                 # exact .5 ties of the requant
        rows.append((acc, 1, 0, 1 << 14, 15, 0, 1, _wb(acc, 1, 0, 1 << 14, 15, 0, 1)))
    return _write(path, rows, (8, 1, 2, 4, 2, 4, 1, 8))


# ---------------------------------------------------------------- mq_nlu: "fn x idx f sh zero y"
def nlu_vectors(path, r):
    rows = []

    def add(fn, x):
        a = nlu.address(fn, x)
        rows.append((nlu.FN_CODE[fn], x, nlu.BASE[fn] + a['i'], a['f'], a['sh'], a['zero'],
                     nlu.evaluate(fn, x)))

    for fn in ('sigmoid', 'softplus'):
        for x in range(-2200, 2201):                           # every input of the grid + clamp
            add(fn, x)
        for _ in range(2000):
            add(fn, _rnd_signed(r, 32))
        for x in (-(1 << 31), (1 << 31) - 1, -2049, 2049, -32768, 32767):
            add(fn, x)
    for _ in range(20000):                                     # exp2: the live range
        add('exp2', -r.randrange(0, 17 << 19))
    for _ in range(2000):
        add('exp2', _rnd_signed(r, 32))
    for p in (0, 1, (1 << 31) - 1, -1, -(1 << 19), -(1 << 19) + 1, -(1 << 19) - 1, -(15 << 19),
              -(16 << 19) + 1, -(16 << 19), -(16 << 19) - 1, -(1 << 31), -(1 << 30)):
        add('exp2', p)
    for _ in range(20000):                                     # rsqrt: 16 .. 2^32 - 1, all octaves
        bits = r.randrange(5, 33)
        add('rsqrt', r.randrange(1 << (bits - 1), 1 << bits))
    for n in (16, 17, 31, 32, 63, 64, 65535, 65536, 65537, 1 << 17, (1 << 18) - 1, 1 << 18,
              (1 << 30) - 1, 1 << 30, (1 << 31) - 1, 1 << 31, (1 << 32) - 1, 3 << 16, 3 << 17):
        add('rsqrt', n)
    return _write(path, rows, (1, 8, 3, 3, 2, 1, 4))


GENERATORS = dict(rsh=rsh_vectors, sat=sat_vectors, lane=lane_vectors, wb=wb_vectors, nlu=nlu_vectors)


def main(out):
    out.mkdir(parents=True, exist_ok=True)
    for name, gen in GENERATORS.items():
        n = gen(out / f'{name}.hex', random.Random(sum(map(ord, name))))
        print(f'vectors {name:6s} {n:8d}')


if __name__ == '__main__':
    main(Path(sys.argv[1]))
