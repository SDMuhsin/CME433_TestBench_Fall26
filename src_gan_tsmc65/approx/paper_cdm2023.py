"""Error metrics of the Amirafshar et al. 2023 carry-disregard multipliers vs the paper's
Tables IV (CDM8, 8 bit) and V (CDM16, 16 bit), plus a gate-count trend vs the paper's area.

  python3 -m src_gan_tsmc65.approx.paper_cdm2023 [--jobs 40] [--no16]
Both tables exhaustive (2^16 / 2^32 pairs), as in the paper (Sec. VII-B). Conventions (Table
III): MED = mean ED, NMED = MED / (2^N - 1)^2, MRED over non-zero products, NoEB =
2N - log2(1 + sqrt(MSE)), PC = share of exact outputs. 8 bit: the analytic model (eq. 8) and
the bit-level netlist are compared on all inputs. Writes approx/results/cdm2023_error.md.
"""
import argparse
from pathlib import Path

import numpy as np

from . import cdm
from .emit import _needed
from .exhaustive import unsigned_stats
from .metrics import ErrorStats

# Table IV: (x, y) -> (area um^2, power uW, delay ns, MED, NMED, MRED, NoEB, PC %)
T4 = {
    (1, 1): (300.6, 85.61, 0.76, 0, 0, 0, 16, 100),
    (4, 4): (257.7, 76.777, 0.65, 97.75, 0.00150, 0.0133, 8.49, 52.9),
    (5, 1): (269.2, 78.071, 0.641, 14.25, 0.00022, 0.0039, 11.29, 59.57),
    (6, 2): (253.2, 74.851, 0.584, 35.25, 0.00054, 0.0081, 10.10, 51.1),
    (7, 3): (237.5, 70.826, 0.563, 89.25, 0.00137, 0.0164, 8.87, 42.52),
    (7, 4): (227.7, 66.27, 0.529, 157.25, 0.00242, 0.0241, 8.08, 37.09),
    (8, 4): (216.3, 62.704, 0.522, 225.25, 0.00346, 0.0319, 7.63, 33.58),
    (9, 5): (200.6, 58.337, 0.486, 441.25, 0.00678, 0.0518, 6.66, 29.05),
    (10, 6): (193.1, 55.601, 0.502, 777.25, 0.01195, 0.0766, 5.81, 26.40),
    (10, 7): (183.8, 52.056, 0.502, 1321.25, 0.02032, 0.1084, 5.00, 24.63),
    (10, 8): (171, 48.724, 0.502, 2409.25, 0.03705, 0.1548, 4.09, 23.06),
    (10, 9): (166.2, 47.57, 0.505, 3689.25, 0.05673, 0.1936, 3.36, 22.43),
    (10, 10): (156.1, 41.548, 0.548, 4713.25, 0.07248, 0.2145, 2.85, 22.26),
}
# Table V: digits -> (area um^2, MED, NMED, MRED, NoEB, PC %)
T5 = {
    '0000': (1318.6, 8222699, 0.001914, 0.009806, 7.98, 19.61),
    '3000': (1298.9, 8222699, 0.001914, 0.009806, 7.98, 13.85),
    '7000': (1237.7, 8222699, 0.001914, 0.009806, 7.98, 8.19),
    '8000': (1225.2, 8222699, 0.001914, 0.009806, 7.98, 7.55),
    '8330': (1183.9, 8222766, 0.001914, 0.009815, 7.98, 5.12),
    'b330': (1155.5, 8222766, 0.001914, 0.009816, 7.98, 4.49),
    'f770': (1022.5, 8223980, 0.001914, 0.009974, 7.98, 2.04),
    'f880': (990.6, 8225459, 0.001915, 0.010089, 7.98, 1.81),
    'f883': (970.6, 8609497, 0.002, 0.010976, 7.95, 1.63),
    'fbb3': (905.7, 8610775, 0.002, 0.011462, 7.95, 1.33),
    'fff7': (825.1, 23076674, 0.005373, 0.026846, 6.66, 1.07),
    'fff8': (809.2, 36831042, 0.008575, 0.035407, 5.92, 1.04),
    'fffb': (773.3, 156630850, 0.036469, 0.078296, 3.59, 1.00),
    'ffff': (767.9, 307625794, 0.071626, 0.107794, 2.35, 0.99),
}
OUT = Path(__file__).resolve().parent / 'results' / 'cdm2023_error.md'
U = np.arange(256)
A, B = np.meshgrid(U, U, indexing='ij')


def _c(ours, paper, fmt):
    rel = f' ({100 * (ours / paper - 1):+.1f} %)' if paper else ''
    return f'{ours:{fmt}} / {paper:{fmt}}{rel}'


def _gates(m):
    """2-input gates (AND / OR / XOR) + inverters of the netlist before the final adder."""
    return sum(m.net.ops[k][0] in ('and', 'or', 'xor', 'not') for k in _needed(m.net, m.x + m.y))


def _metrics(r):
    return (r['MED'], r['NMED'], r['MRED'], r['NoEB'], 100 * (1 - r['ER']))


def _row(name, ours, paper):
    fmts = ('.2f', '.5f', '.4f', '.2f', '.2f')
    return f'| {name} | ' + ' | '.join(_c(o, p, f) for o, p, f in zip(ours, paper, fmts)) + ' |'


def rows8():
    rows, gates = [], {}
    for (x, y), p in T4.items():
        ref = cdm.unsigned8(A, B, x, y)
        m = cdm.cdm(x, y, 'unsigned')
        same = int((m.products(A, B).reshape(256, 256) == ref).sum())
        r = ErrorStats(255 ** 2).add(ref, A * B).result(16)
        gates[(x, y)] = _gates(m)
        name = 'Exact8 (cd1 / cd1)' if x == 1 else cdm.name(x, y)
        rows.append(_row(name, _metrics(r), p[3:]) + f' {same}/65536 |')
        print(rows[-1], flush=True)
    return rows, gates


def trend(gates):
    ex = gates[(1, 1)]
    out = []
    for (x, y), p in T4.items():
        ar = 100 * (p[0] / T4[(1, 1)][0] - 1)
        out.append(f'| {"Exact8" if x == 1 else cdm.name(x, y)} | {p[0]} ({ar:+.1f} %) | '
                   f'{p[1]} | {p[2]} | {gates[(x, y)]} ({100 * (gates[(x, y)] / ex - 1):+.1f} %) |')
    xs = np.array([T4[k][0] for k in T4]), np.array([gates[k] for k in T4])
    rank = [np.argsort(np.argsort(v)) for v in xs]
    rho = np.corrcoef(*rank)[0, 1]
    return out, rho


def rows16(jobs):
    rows = []
    for d, p in T5.items():
        r = unsigned_stats(cdm.Cdm16, 16, (d,), jobs=jobs)
        rows.append(_row(f'CDM16_{d}', _metrics(r), p[1:]))
        print(rows[-1], flush=True)
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--jobs', type=int, default=40)
    ap.add_argument('--no16', action='store_true')
    args = ap.parse_args()
    head = '| Design | MED (ours / paper) | NMED | MRED | NoEB | PC % |'
    r8, gates = rows8()
    t8 = [head + ' netlist == eq. 8 |', '|---' * 7 + '|'] + r8
    tr, rho = trend(gates)
    tt = ['| Design | paper area um^2 (vs Exact8) | paper power uW | paper delay ns | '
          'our gates before the final adder (vs Exact8) |', '|---' * 5 + '|'] + tr
    t16 = [] if args.no16 else [head, '|---' * 6 + '|'] + rows16(args.jobs)
    OUT.parent.mkdir(exist_ok=True)
    OUT.write_text(
        '# Amirafshar et al. 2023 (carry-disregard multipliers): error metrics vs the paper\n\n'
        'Generated by `python3 -m src_gan_tsmc65.approx.paper_cdm2023`. Model: `approx/cdm.py`. '
        'Unsigned, exhaustive. MED = mean |E|, NMED = MED / (2^N - 1)^2, MRED over non-zero '
        'products, NoEB = 2N - log2(1 + RMSE), PC = share of exact outputs (Table III).\n\n'
        '## Table IV: CDM8 (8 x 8)\n\n' + '\n'.join(t8) + '\n\n'
        '## Hardware trend (Table IV, Nangate 45 nm) vs gate count of our netlists\n\n'
        'Gate count = AND / OR / XOR / NOT of the bit-level netlist (partial products, XOR '
        'columns, Dadda tree), without the final adder; a proxy, not a synthesis result. '
        f'Spearman rank correlation with the paper\'s area: {rho:.3f}.\n\n'
        + '\n'.join(tt) + '\n'
        + ('' if args.no16 else '\n## Table V: CDM16 (16 x 16)\n\n' + '\n'.join(t16) + '\n'))


if __name__ == '__main__':
    main()
