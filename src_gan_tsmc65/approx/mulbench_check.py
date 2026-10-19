"""RTL == Python model check and error metrics of the multiplier-bench designs (approx/mulbench.py).

  python3 -m src_gan_tsmc65.approx.mulbench_check --width 16 [--n 1000000] [design ...]
Vectors: N = 16: n uniform random operand pairs (seed 1) plus all pairs of corner values (zero,
+-1, powers of two and their neighbours, extremes, bit patterns); N = 8: all 65,536 pairs.
Each syn/mulbench/rtl/w<N>/<design>.v runs in iverilog (syn/mulbench/tb/tb_mul_vec.v) and must
equal the model on every vector. Metrics over the random (or all) pairs: unsigned NMED = MED /
(2^N - 1)^2, signed NMED = MED / 2^(2N-2); MRED over non-zero products, MRED_all over all
pairs (Yin's convention); the 16-bit HAM also on the paper's step-8 grid (Table III convention,
model only). Writes approx/results/mulbench_w<N>_error.md.
"""
import argparse
import subprocess
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import numpy as np

from ..common.paths import BUILD
from .metrics import ErrorStats
from .mulbench import RTL, designs

HERE = Path(__file__).resolve().parent
TB = HERE.parent / 'syn' / 'mulbench' / 'tb' / 'tb_mul_vec.v'
WORK = BUILD / 'mulbench'


def corners(n):
    m = (1 << n) - 1
    h = 1 << (n - 1)
    v = {0, 1, 2, 3, m, m - 1, h, h + 1, h - 1, h - 16, h + 16, m - 15, m >> (n // 2),
         m ^ (m >> (n // 2)), int('01' * (n // 2), 2), int('10' * (n // 2), 2)}
    for k in range(n):
        v |= {1 << k, (1 << k) - 1, ((1 << k) + 1) & m, (-(1 << k)) & m}
    v = np.array(sorted(v), np.int64)
    a, b = np.meshgrid(v, v, indexing='ij')
    return a.ravel(), b.ravel()


def vectors(n, count):
    """(a, b, number of metric pairs at the front)."""
    if n == 8:
        u = np.arange(256)
        a, b = np.meshgrid(u, u, indexing='ij')
        return a.ravel(), b.ravel(), 65536
    rng = np.random.default_rng(1)
    ca, cb = corners(n)
    return (np.concatenate([rng.integers(0, 1 << n, count), ca]),
            np.concatenate([rng.integers(0, 1 << n, count), cb]), count)


def to_signed(v, bits):
    return np.where(v >= 1 << (bits - 1), v - (1 << bits), v)


def run_rtl(n, name, vec):
    img = WORK / f'w{n}_{name}.vvp'
    subprocess.run(['iverilog', '-g2012', f'-Ptb_mul_vec.N={n}', '-o', str(img), str(TB),
                    str(RTL / f'w{n}' / f'{name}.v')], check=True)
    out = subprocess.run(['vvp', '-n', str(img), f'+VEC={vec}'], check=True, capture_output=True,
                         text=True).stdout.split()
    return np.array([int(w, 16) for w in out if len(w) == n // 2], np.int64)


def grid_stats(d, count):
    """Shi Table III convention: a, b on the step-8 grid of -2^15..2^15-1, MRED = mean
    |E| / max(1, |exact|) over all pairs, NMED = MED / 2^30 (count random grid pairs)."""
    rng = np.random.default_rng(2)
    a, b = (rng.integers(-4096, 4096, count) * 8 for _ in range(2))
    x = a * b
    e = np.abs(d.model.products(a, b) - x)
    return 100 * float((e / np.maximum(1, np.abs(x))).mean()), float(e.mean()) / 2 ** 30


def row(n, d, ua, ub, p_rtl, k):
    a, b = (to_signed(ua, n), to_signed(ub, n)) if d.signed else (ua, ub)
    model = d.model.products(a, b)
    rtl = to_signed(p_rtl, 2 * n) if d.signed else p_rtl
    same = int((model == rtl).sum())
    mx = 1 << (2 * n - 2) if d.signed else ((1 << n) - 1) ** 2
    s = ErrorStats(mx).add(rtl[:k], a[:k] * b[:k]).result()
    grid = '-'
    if n == 16 and d.name.startswith('s_h9c1'):
        g = grid_stats(d, k)
        grid = f'{g[0]:.3f} % / {1e3 * g[1]:.3f}e-3'
    return (f'| `{d.name}` | {same}/{len(rtl)} | {100 * s["ER"]:.2f} % | {s["NMED"]:.3e} | '
            f'{100 * s["MRED"]:.3f} % | {100 * s["MRED_all"]:.3f} % | {s["bias"]:+.4g} | '
            f'{s["max_abs"]} | {grid} |'), same == len(rtl)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--width', type=int, default=16, choices=(8, 16))
    ap.add_argument('--n', type=int, default=1_000_000)
    ap.add_argument('designs', nargs='*')
    args = ap.parse_args()
    n, reg = args.width, designs(args.width)
    names = args.designs or list(reg)
    WORK.mkdir(parents=True, exist_ok=True)
    ua, ub, k = vectors(n, args.n)
    vec = WORK / f'vectors_w{n}.hex'
    vec.write_text('\n'.join(f'{x:0{n // 4}x}{y:0{n // 4}x}' for x, y in zip(ua, ub)) + '\n')
    with ThreadPoolExecutor(len(names)) as ex:
        outs = dict(zip(names, ex.map(lambda nm: run_rtl(n, nm, vec), names)))
    rows = ['| Design | RTL == model | ER | NMED | MRED (non-zero) | MRED_all | bias | max abs error | '
            'step-8 grid MRED / NMED (Table III) |', '|---' * 9 + '|']
    ok = True
    for nm in names:
        r, good = row(n, reg[nm], ua, ub, outs[nm], k)
        rows.append(r)
        ok &= good
        print(r, flush=True)
    if not args.designs:
        what = ('all 65,536 pairs' if n == 8 else
                f'{k:,} uniform random pairs (seed 1) + {len(ua) - k:,} corner pairs; metrics over the random pairs')
        (HERE / 'results' / f'mulbench_w{n}_error.md').write_text(
            f'# Multiplier bench, N = {n}: RTL check and error metrics\n\n'
            f'Generated by `python3 -m src_gan_tsmc65.approx.mulbench_check --width {n}`: {what}. '
            f'Unsigned NMED = MED / (2^{n} - 1)^2, signed NMED = MED / 2^{2 * n - 2}.\n\n'
            + '\n'.join(rows) + '\n')
    print('PASS' if ok else 'FAIL')
    raise SystemExit(0 if ok else 1)


if __name__ == '__main__':
    main()
