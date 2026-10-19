"""Error metrics of the Park, Kung & Lee 2023 approximate radix-4 Booth multiplier vs the paper.

  python3 -m src_gan_tsmc65.approx.paper_park2023 [--jobs 44] [--quick]
* Table III (16 x 16 signed, exhaustive like the paper; NMED = MED / 2^30, MRED over non-zero
  products, PRED = P(RED < 2 %)) for the paper's (wG, wA) points, with the OR(neg, PP) bit of
  Fig. 1 and without it (neg_or=False). --quick uses 4 M random pairs instead (seconds).
* Fig. 3 / Fig. 4: mean and quartiles of the error for (wG, 0), (0, wA) and (wG, wA)
  (1 M uniform random pairs, as the paper).
* The bench designs (approx/mulbench.py park_*): ER, MAE, bias over all pairs and over b >= 0
  (activations), max |E|, NMED, MRED, and the zero products a * 0 / 0 * b that are not 0
  (N = 8 exhaustive, N = 16: 4 M random pairs, all-pairs zero checks).
Writes approx/results/park2023_error.md.
"""
import argparse
from pathlib import Path

import numpy as np

from .exhaustive import signed_stats
from .metrics import ErrorStats
from .park import park

OUT = Path(__file__).resolve().parent / 'results' / 'park2023_error.md'
# (wG, wA) -> paper Table III (NMED 1e-6, MRED 1e-4, PRED %)
TABLE3 = {(0, 0): (0.00, 0.00, 100.00), (10, 10): (4.37, 1.53, 99.93),
          (12, 12): (6.08, 5.34, 99.82), (14, 14): (18.52, 18.54, 99.42)}
# Fig. 3 / Fig. 4 box centres read off the plots (1e5), approximate
FIG3 = {(10, 0): 0.0, (13, 0): 0.15, (14, 0): 0.3, (15, 0): 0.7,
        (0, 13): -0.2, (0, 14): -0.4, (0, 15): -0.7}


def _random(n, count, seed, b_min=None):
    rng = np.random.default_rng(seed)
    lo, hi = -(1 << (n - 1)), 1 << (n - 1)
    return rng.integers(lo, hi, count), rng.integers(lo if b_min is None else b_min, hi, count)


def table3(jobs, quick):
    rows = ['| (wG, wA) | OR(neg7, PP) | NMED 1e-6 (ours / paper) | MRED 1e-4 (ours / paper) | '
            'PRED % (ours / paper) | ER | bias |', '|---' * 7 + '|']
    a, b = _random(16, 1 << 22, 3)
    for (wg, wa), p in TABLE3.items():
        for neg_or in (True, False):
            if quick:
                r = ErrorStats(1 << 30).add(park(16, wg, wa, neg_or=neg_or).products(a, b), a * b).result()
            else:
                r = signed_stats(park, 16, (16, wg, wa, False, neg_or), jobs=jobs)
            rows.append(f'| ({wg}, {wa}) | {"yes (Fig. 1)" if neg_or else "no"} | '
                        f'{1e6 * r["NMED"]:.2f} / {p[0]:.2f} | {1e4 * r["MRED"]:.2f} / {p[1]:.2f} | '
                        f'{100 * r["PRED"]:.2f} / {p[2]:.2f} | {r["ER"]:.4f} | {r["bias"]:+.0f} |')
            print(rows[-1], flush=True)
    return rows


def fig34():
    a, b = _random(16, 1 << 20, 4)
    rows = ['| (wG, wA) | mean E (1e5) | median | Q1 / Q3 | paper (Fig. 3 box centre) |', '|---' * 5 + '|']
    cfgs = [(w, 0) for w in range(10, 17)] + [(0, w) for w in range(10, 17)] + [
        (10, 10), (11, 11), (12, 12), (13, 13), (14, 14), (15, 14), (16, 15)]
    for cfg in cfgs:
        e = (park(16, *cfg).products(a, b) - a * b) / 1e5
        q1, q3 = np.percentile(e, (25, 75))
        rows.append(f'| {cfg} | {e.mean():+.3f} | {np.median(e):+.3f} | {q1:+.3f} / {q3:+.3f} | '
                    f'{FIG3.get(cfg, "-")} |')
    return rows


def design_rows(n, designs):
    """Bench-design metrics; designs = [(name, wg, wa, zero_fix, neg_or)]."""
    if n == 8:
        v = np.arange(-128, 128)
        a, b = (x.ravel() for x in np.meshgrid(v, v, indexing='ij'))
        ap, bp = a[b >= 0], b[b >= 0]
    else:
        a, b = _random(16, 1 << 22, 5)
        ap, bp = _random(16, 1 << 22, 6, b_min=0)
    v = np.arange(-(1 << (n - 1)), 1 << (n - 1))
    z = np.zeros_like(v)
    rows = ['| Design | (wG, wA) | ER | MAE | bias | bias b >= 0 | max abs E | NMED | MRED | '
            'a * 0 != 0 | 0 * b != 0 |', '|---' * 11 + '|']
    for name, wg, wa, zf, no in designs:
        m = park(n, wg, wa, zf, no)
        r = ErrorStats(1 << (2 * n - 2)).add(m.products(a, b), a * b).result()
        rp = ErrorStats(1 << (2 * n - 2)).add(m.products(ap, bp), ap * bp).result()
        zb, za = int((m.products(v, z) != 0).sum()), int((m.products(z, v) != 0).sum())
        rows.append(f'| `{name}` | ({wg}, {wa}) | {100 * r["ER"]:.2f} % | {r["MED"]:.4g} | '
                    f'{r["bias"]:+.4g} | {rp["bias"]:+.4g} | {r["max_abs"]} | {r["NMED"]:.3e} | '
                    f'{100 * r["MRED"]:.3f} % | {zb} / {v.size} | {za} / {v.size} |')
        print(rows[-1], flush=True)
    return rows


def bench_designs(n):
    from .mulbench import PARK
    return [(f'park_{k}', *cfg) for k, cfg in PARK[n].items()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--jobs', type=int, default=44)
    ap.add_argument('--quick', action='store_true')
    args = ap.parse_args()
    d16, d8 = design_rows(16, bench_designs(16)), design_rows(8, bench_designs(8))
    f34 = fig34()
    t3 = table3(args.jobs, args.quick)
    how = '4 M random pairs (--quick)' if args.quick else 'exhaustive, 2^32 pairs'
    OUT.write_text(
        '# Park, Kung & Lee 2023 (approximate radix-4 Booth): error metrics vs the paper\n\n'
        'Generated by `python3 -m src_gan_tsmc65.approx.paper_park2023`. Signed operands, '
        'NMED = MED / 2^(2N-2).\n\n'
        f'## Table III, 16 x 16 ({how})\n\n' + '\n'.join(t3) + '\n\n'
        '## Fig. 3 / Fig. 4 error distribution (1 M uniform random pairs, E = approx - exact)\n\n'
        + '\n'.join(f34) + '\n\n'
        '## Bench designs, N = 16 (4 M uniform random pairs; b >= 0: 4 M pairs with b uniform in '
        '[0, 2^15); zero checks over all 65,536 values)\n\n' + '\n'.join(d16) + '\n\n'
        '## Bench designs, N = 8 (exhaustive; b >= 0 = the 32,768 pairs with b >= 0)\n\n'
        + '\n'.join(d8) + '\n')
    print(OUT)


if __name__ == '__main__':
    main()
