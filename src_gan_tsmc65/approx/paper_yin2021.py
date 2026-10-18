"""Error metrics of the Yin et al. 2021 DR-ALMs and Mitchell's LM vs the paper's Tables 2, 5, 6.

  python3 -m src_gan_tsmc65.approx.paper_yin2021 [--samples 10000000] [--big 1000000] [--jobs 40]
Unsigned 8 / 16 bit exhaustive, 32 bit --big uniform random pairs (Python ints); signed 8 bit
exhaustive, signed 16 bit --samples uniform random pairs (fixed seeds). Paper conventions found
by matching: MRED averages RED over all pairs (RED = 0 when the product is 0), NMED = MED /
(2^n - 1)^2 unsigned, MED / 2^(2n-1) signed. Writes approx/results/yin2021_error.md.
"""
import argparse
from pathlib import Path

import numpy as np

from . import dralm
from .exhaustive import signed_stats, unsigned_stats

TS = (None, 12, 10, 8, 7, 6, 5, 4, 3)
# paper Table 2 (unsigned): {n: {t: (MRED %, NMED 1e-2, WCE, WCRE %)}}, WCE in units of UNIT[n]
UNIT = {8: 1e3, 16: 1e6, 32: 1e16}
T2 = {
    8: {None: (3.76, 0.933, 4.096, 11.111), 7: (2.74, 0.685, 3.969, 11.111),
        6: (2.91, 0.699, 4.225, 11.581), 5: (4.32, 0.963, 5.888, 18.75),
        4: (8.87, 1.929, 11.263, 37.494), 3: (20.22, 4.287, 20.479, 74.994)},
    16: {None: (3.85, 0.926, 268.435, 11.111), 12: (3.81, 0.917, 268.861, 11.129),
         10: (3.72, 0.895, 270.43, 11.194), 8: (3.43, 0.823, 276.726, 11.455),
         7: (3.17, 0.762, 285.114, 11.802), 6: (3.03, 0.73, 301.892, 12.496),
         5: (3.81, 0.923, 385.876, 18.750), 4: (7.67, 1.821, 738.198, 37.50),
         3: (18.41, 4.133, 1342.18, 75.000)},
    32: {None: (3.88, 5.201, 7.201, 11.111), 12: (3.85, 5.16, 7.192, 11.125),
         10: (3.76, 5.045, 7.232, 11.178), 8: (3.47, 4.663, 7.28, 11.438),
         7: (3.22, 4.316, 7.447, 11.785), 6: (3.09, 4.077, 7.997, 12.470),
         5: (3.93, 5.011, 9.229, 18.680), 4: (8.11, 10.215, 19.364, 37.419),
         3: (20.40, 25.688, 35.946, 74.897)},
}
# Tables 5 / 6 (signed): {n: {t: (NMED 1e-2, MRED %, WCE, WCRE %)}}, WCE in 1e3 / 1e6
T56 = {
    8: {3: (2.07, 19.11, 5.12, 75.0), 4: (0.92, 8.59, 2.82, 75.0), 5: (0.48, 4.84, 1.47, 75.0),
        6: (0.38, 3.94, 1.15, 75.0), 7: (0.39, 4.04, 1.09, 75.0)},
    16: {3: (2.220, 14.76, 234.88, 75.0), 4: (1.243, 7.63, 167.77, 50.0),
         5: (0.527, 3.57, 83.86, 50.0), 6: (0.272, 2.44, 45.07, 50.0),
         7: (0.256, 2.51, 43.23, 100.0)},
}
OUT = Path(__file__).resolve().parent / 'results' / 'yin2021_error.md'


def _c(ours, paper, fmt):
    rel = f' ({100 * (ours / paper - 1):+.1f} %)' if paper else ''
    return f'{ours:{fmt}} / {paper:{fmt}}{rel}'


def _name(t):
    return 'LM (Mitchell)' if t is None else f'DR-ALM-{t}'


def _big(n, t, samples, seed=7):
    """Unsigned n > 30 bit metrics on Python ints: (MRED_all, NMED, WCE, WCRE)."""
    rng = np.random.default_rng(seed)
    a = rng.integers(0, 1 << n, samples, dtype=np.uint64).astype(object)
    b = rng.integers(0, 1 << n, samples, dtype=np.uint64).astype(object)
    ex = a * b
    e = np.abs(dralm.unsigned(a, b, n, t) - ex)
    nz = ex != 0
    red = (e[nz] / ex[nz]).astype(float)
    return (red.sum() / samples, float(e.sum()) / samples / ((1 << n) - 1) ** 2,
            int(e.max()), float(red.max()))


def unsigned_rows(args):
    rows = []
    for n in (8, 16, 32):
        for t in TS:
            if t not in T2[n]:
                continue
            if n == 32:
                mred, nmed, wce, wcre = _big(n, t, args.big)
            else:
                r = unsigned_stats(dralm.build, n, (n, t, 'paper', False), jobs=args.jobs)
                mred, nmed, wce, wcre = r['MRED_all'], r['NMED'], r['max_abs'], r['WCRE']
            p = T2[n][t]
            rows.append(f'| {n} | {_name(t)} | {_c(100 * mred, p[0], ".2f")} | '
                        f'{_c(100 * nmed, p[1], ".3f")} | {_c(wce / UNIT[n], p[2], ".3f")} | '
                        f'{_c(100 * wcre, p[3], ".3f")} |')
            print(rows[-1], flush=True)
    return rows


def signed_rows(args):
    rows = []
    for n in (8, 16):
        for t, p in T56[n].items():
            for sign in ('paper', 'exact'):
                r = signed_stats(dralm.build, n, (n, t, sign), jobs=args.jobs,
                                 samples=0 if n == 8 else args.samples,
                                 max_out=1 << (2 * n - 1))
                rows.append(f'| {n} | signed DR-ALM-{t} | {sign} | {_c(100 * r["NMED"], p[0], ".3f")} | '
                            f'{_c(100 * r["MRED_all"], p[1], ".2f")} | '
                            f'{_c(r["max_abs"] / UNIT[n], p[2], ".3f")} | '
                            f'{_c(100 * r["WCRE"], p[3], ".2f")} |')
                print(rows[-1], flush=True)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--samples', type=int, default=10_000_000)
    ap.add_argument('--big', type=int, default=1_000_000)
    ap.add_argument('--jobs', type=int, default=40)
    args = ap.parse_args()
    u = ['| n | Design | MRED % (ours / paper) | NMED 1e-2 | WCE (1e3 / 1e6 / 1e16) | WCRE % |',
         '|---' * 6 + '|'] + unsigned_rows(args)
    s = ['| n | Design | sign units | NMED 1e-2 (ours / paper) | MRED % | WCE (1e3 / 1e6) | '
         'WCRE % |', '|---' * 7 + '|'] + signed_rows(args)
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(
        '# Yin et al. 2021 (DR-ALM): error metrics vs the paper\n\n'
        'Generated by `python3 -m src_gan_tsmc65.approx.paper_yin2021`. Model: '
        '`approx/dralm.py`. Unsigned (Table 2): 8 and 16 bit exhaustive, 32 bit '
        f'{args.big:,} uniform random pairs. MRED over all pairs, NMED = MED / (2^n - 1)^2.\n\n'
        + '\n'.join(u) + '\n\n'
        'Signed (Tables 5-6): 8 bit exhaustive, 16 bit '
        f'{args.samples:,} uniform random pairs; NMED = MED / 2^(2n-1). Sign units "paper": '
        "|x| ~ ~x | 1 and -P ~ ~P | 1 (Sec. 3, Fig. 3); \"exact\": two's-complement negation "
        '(not in the paper, for comparison).\n\n' + '\n'.join(s) + '\n')


if __name__ == '__main__':
    main()
