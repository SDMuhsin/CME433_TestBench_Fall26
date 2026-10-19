"""Error metrics of the Zhu et al. 2022 approximate radix-256 Booth multiplier vs the paper.

  python3 -m src_gan_tsmc65.approx.paper_zhu2022 [--jobs 32]
* Table III: digit ranges, PPA / PPB, P_k and the per-section MAE of eq. (5) from the 32 input
  patterns of every section, against the printed table.
* Table V (16 x 16 signed, exhaustive 2^32 pairs): NMED, MRED (non-zero products), PRED =
  P(RED < 2 %) of the AR256 design; NMED normalised by 2^30 (max |product|) and by 2^31.
* Netlist (zhu.zhu) == closed-form model (zhu.Model): exhaustive at N = 8, 4 M random at N = 16.
* Bench designs (approx/mulbench.py r256_*): ER, MAE, bias over all pairs and b >= 0, max |E|,
  NMED, MRED, zero products a * 0 / 0 * b that are not 0, GAN-like bias / MAE (the bench's
  power stimulus, 200 k pairs).
Writes approx/results/zhu2022_error.md.
"""
import argparse
import importlib.util
from pathlib import Path

import numpy as np

from . import r256
from .exhaustive import signed_stats
from .metrics import ErrorStats
from .zhu import Model, zhu

HERE = Path(__file__).resolve().parent
OUT = HERE / 'results' / 'zhu2022_error.md'
STIM = HERE.parent / 'syn' / 'mulbench' / 'stimulus.py'
# Table III as printed: t -> (d_k min, d_k max, PPA, PPB, P_k, MAE) in units of X
TABLE3 = {0: (0, 16, 0, 8, 8, 8), 1: (16, 32, 16, 8, 24, 8), 2: (32, 48, 32, 8, 40, 8),
          3: (48, 64, 32, 16, 48, 16), 4: (64, 80, 64, 8, 72, 8), 5: (80, 96, 64, 16, 80, 16),
          6: (96, 112, 64, 32, 96, 16), 7: (112, 128, 64, 64, 128, 16),
          8: (-128, -112, -64, -64, -128, 16), 9: (-112, -96, -64, -32, -96, 16),
          10: (-96, -80, -64, -16, -80, 16), 11: (-80, -64, -64, -8, -72, 8),
          12: (-64, -48, -32, -16, -48, 16), 13: (-48, -32, -32, -8, -40, 8),
          14: (-32, -16, -16, -8, -24, 8), 15: (-16, 0, 0, -8, -8, 8)}
TABLE5 = (0.460e-4, 0.19e-2, 99.02e-2)          # AR256: NMED, MRED, PRED


def table3():
    rows = ['| t | d_k range (ours / paper) | PPA, PPB | P_k | MAE (ours / paper) |', '|---' * 5 + '|']
    ok = True
    for t, (lo, hi, pa, pb, pk, mae) in TABLE3.items():
        pat = np.arange(32)                          # y3 y2 y1 y0 y-1
        dk = (t - 16 * (t >= 8)) * 16 + (pat >> 1) + (pat & 1)
        a, b, neg = r256.section(t)
        s = -1 if neg else 1
        p = s * (a + b)
        m = int(np.abs(p - dk).max())
        same = (dk.min(), dk.max(), s * a, s * b, p, m) == (lo, hi, pa, pb, pk, mae)
        ok &= same
        rows.append(f'| {t:04b} | [{dk.min()}, {dk.max()}] / [{lo}, {hi}] | {s * a}X, {s * b}X | '
                    f'{p}X | {m}X / {mae}X |' + ('' if same else ' **differs**'))
    return rows, ok


def table5(jobs):
    rows = ['| design (16 x 16) | NMED / 2^30 | NMED / 2^31 | MRED | PRED | ER | bias | max abs E | '
            'paper NMED / MRED / PRED |', '|---' * 9 + '|']
    for d in (6, 8, 10):
        for zf in (False, True):
            r = signed_stats(Model, 16, (16, d, zf), jobs=jobs)
            paper = ('%.3e / %.2f %% / %.2f %%' % (TABLE5[0], 100 * TABLE5[1], 100 * TABLE5[2])
                     if d == 8 and not zf else '-')
            rows.append(f'| d = {d}{" + zero fix" if zf else ""} | {r["NMED"]:.3e} | '
                        f'{r["NMED"] / 2:.3e} | {100 * r["MRED"]:.4f} % | {100 * r["PRED"]:.3f} % | '
                        f'{100 * r["ER"]:.3f} % | {r["bias"]:+.4g} | {r["max_abs"]} | {paper} |')
            print(rows[-1], flush=True)
    return rows


def _gan(n, count=200_000):
    spec = importlib.util.spec_from_file_location('mb_stimulus', STIM)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    a, b = mod.stream(n, 'gan', True, count)
    return np.where(a >= 1 << (n - 1), a - (1 << n), a), b


def _pairs(n):
    if n == 8:
        v = np.arange(-128, 128)
        a, b = (x.ravel() for x in np.meshgrid(v, v, indexing='ij'))
        return a, b, a[b >= 0], b[b >= 0]
    rng = np.random.default_rng(5)
    lo, hi = -(1 << 15), 1 << 15
    a, b = rng.integers(lo, hi, (2, 1 << 22))
    return a, b, rng.integers(lo, hi, 1 << 22), rng.integers(0, hi, 1 << 22)


def model_check(n, cfgs):
    a, b, _, _ = _pairs(n)
    bad = [k for k, (d, zf) in cfgs.items() if not (zhu(n, d, zf).products(a, b)
                                                     == Model(n, d, zf).products(a, b)).all()]
    return f'N = {n}: netlist == closed form on {a.size:,} pairs for ' + (
        'all designs' if not bad else 'all but ' + ', '.join(bad))


def design_rows(n, cfgs):
    a, b, ap, bp = _pairs(n)
    ga, gb = _gan(n)
    v = np.arange(-(1 << (n - 1)), 1 << (n - 1))
    z = np.zeros_like(v)
    mx = 1 << (2 * n - 2)
    rows = ['| Design | d | ER | MAE | bias | bias b >= 0 | max abs E | NMED | MRED | a * 0 != 0 | '
            '0 * b != 0 | GAN-like bias / MAE |', '|---' * 12 + '|']
    for k, (d, zf) in cfgs.items():
        m = Model(n, d, zf)
        r = ErrorStats(mx).add(m.products(a, b), a * b).result()
        rp = ErrorStats(mx).add(m.products(ap, bp), ap * bp).result()
        rg = ErrorStats(mx).add(m.products(ga, gb), ga * gb).result()
        zb, za = int((m.products(v, z) != 0).sum()), int((m.products(z, v) != 0).sum())
        rows.append(f'| `r256_{k}` | {d} | {100 * r["ER"]:.2f} % | {r["MED"]:.4g} | '
                    f'{r["bias"]:+.4g} | {rp["bias"]:+.4g} | {r["max_abs"]} | {r["NMED"]:.3e} | '
                    f'{100 * r["MRED"]:.3f} % | {zb} / {v.size} | {za} / {v.size} | '
                    f'{rg["bias"]:+.4g} / {rg["MED"]:.4g} |')
        print(rows[-1], flush=True)
    return rows


def main():
    from .mulbench import ZHU
    ap = argparse.ArgumentParser()
    ap.add_argument('--jobs', type=int, default=32)
    args = ap.parse_args()
    t3, ok = table3()
    checks = [model_check(n, ZHU[n]) for n in (8, 16)]
    d16, d8 = design_rows(16, ZHU[16]), design_rows(8, ZHU[8])
    t5 = table5(args.jobs)
    OUT.write_text(
        '# Zhu et al. 2022 (approximate radix-256 Booth): error metrics vs the paper\n\n'
        'Generated by `python3 -m src_gan_tsmc65.approx.paper_zhu2022`. Signed operands, b = Y '
        'the recoded operand; NMED = MED / 2^(2N-2) unless stated.\n\n'
        f'## Table III (per-section digit range and MAE of eq. (5)): '
        f'{"all 16 rows match" if ok else "MISMATCH"}\n\n' + '\n'.join(t3) + '\n\n'
        '## Table V error metrics, 16 x 16 (exhaustive, 2^32 pairs)\n\n' + '\n'.join(t5) + '\n\n'
        '## Netlist vs closed-form model\n\n' + '\n'.join(f'- {c}' for c in checks) + '\n\n'
        '## Bench designs, N = 16 (4 M uniform random pairs; b >= 0: 4 M pairs with b uniform in '
        '[0, 2^15); zero checks over all 65,536 values; GAN-like: 200 k pairs of the power '
        'stimulus)\n\n' + '\n'.join(d16) + '\n\n'
        '## Bench designs, N = 8 (exhaustive; b >= 0 = the 32,768 pairs with b >= 0)\n\n'
        + '\n'.join(d8) + '\n')
    print(OUT)


if __name__ == '__main__':
    main()
