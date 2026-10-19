"""Error metrics of the Wang et al. 2026 CLS truncated approximate Booth multipliers vs the paper.

  python3 -m src_gan_tsmc65.approx.paper_wang2026 [--jobs 32]    (~40 min on 44 cores)
* Table II: carry / sum and local error of A4T2C_1 / A4T2C_2 for the 16 inputs, local error
  rates with P(1) = 1/4; encoder K-map flips of CAE1 / CAE2 (32 entries).
* Table IV: explained variance of the 2-bit CTM features (low-bit model).
* Table V: low-bit replacement model (eq. 23) of the constant / CTM compensations, the CLS
  optimum at t = 4, the CLS levels and thresholds for t = 2..6 and the exact-Booth truncation
  sweep of Table III.
* Tables VI / VII: the paper's 8-bit designs and ablations (exhaustive).
* Bench designs (approx/mulbench.py cls_*, tacbm_12): ER, MAE, bias (all, b >= 0), max |E|,
  NMED, MRED, zero products, GAN-like bias / MAE; N = 16 also exhaustive (2^32 pairs).
Writes approx/results/wang2026_error.md.
"""
import argparse
import itertools

import numpy as np

from . import cls, cls_cells, cls_ctm, tacbm
from .exhaustive import signed_stats
from .metrics import ErrorStats
from .netlist import Net
from .paper_zhu2022 import HERE, _gan, _pairs

OUT = HERE / 'results' / 'wang2026_error.md'
# Table II as printed: input x1 x2 x3 x4 -> (A4T2C_1 error, A4T2C_2 error)
TABLE2 = {0b0001: (1, 0), 0b0010: (1, 0), 0b0011: (0, -1), 0b0101: (0, 1), 0b0110: (0, 1),
          0b1000: (-1, 0), 0b1001: (0, -1), 0b1010: (0, -1), 0b1011: (-1, -2), 0b1100: (-1, -1),
          0b1111: (-1, -1)}
# Table V: scheme -> (ME, MAE, NMED, PRED@10 %, Q99)
TABLE5 = {'Const 0000': (-6.5, 6.50, 9.996e-5, 0.9947, 15), 'Const 0010': (-4.5, 5.31, 8.170e-5, 0.9962, 13),
          'Const 0110': (-0.5, 4.19, 6.440e-5, 0.9976, 9), 'CTM1': (-0.5, 4.09, 6.296e-5, 0.9974, 9),
          'CTM2': (-0.5, 4.06, 6.248e-5, 0.9975, 9)}
# Table III (exact encoder / compressor, CLS re-run per t): t -> (NMED, MRED)
TABLE3 = {2: (0.11e-3, 0.27e-2), 3: (0.28e-3, 0.69e-2), 4: (0.50e-3, 1.35e-2),
          5: (1.47e-3, 3.54e-2), 6: (2.79e-3, 6.97e-2)}
# Tables VI / VII: design -> (NMED, MRED, bias or None)
TABLE67 = {'exact_ctm': (0.47e-3, 0.13e-2, -2.67), 'cae1_only': (0.76e-3, 2.03e-2, -2.73),
           'cae2_only': (1.15e-3, 4.35e-2, 43.03), 'a4t2c1_only': (0.47e-3, 1.79e-2, -5.99),
           'a4t2c2_only': (0.53e-3, 1.10e-2, -29.77), 'abmct1': (1.49e-3, 2.45e-2, None),
           'abmct2': (2.05e-3, 3.49e-2, None), 'abmft1': (2.86e-3, 3.77e-2, None)}


def _bits(v, k):
    return [(v >> (k - 1 - i)) & 1 for i in range(k)]


def table2():
    rows = ['| x1 x2 x3 x4 | P | exact | A4T2C_1 CS / err | A4T2C_2 CS / err | paper err |',
            '|---' * 6 + '|']
    net, ok = Net(), True
    rate = {1: [0, 0], 2: [0, 0]}
    for v in range(16):
        x = _bits(v, 4)
        p = 3 ** (4 - sum(x))
        errs = []
        cells = []
        for k, cell in ((1, cls_cells.a4t2c1), (2, cls_cells.a4t2c2)):
            s, c = net.evaluate({'x': x}, list(cell(net, *net.bus('x', 4))), 1)
            e = 2 * c + s - sum(x)
            errs.append(e)
            cells.append(f'{c}{s} / {e:+d}' if e else f'{c}{s}')
            if e:
                rate[k][e < 0] += p
        ok &= tuple(errs) == TABLE2.get(v, (0, 0))
        rows.append(f'| {v:04b} | {p}/256 | {sum(x):b} | {cells[0]} | {cells[1]} | '
                    f'{TABLE2.get(v, (0, 0))} |')
    note = (f'A4T2C_2 local error rate {sum(rate[2])}/256 (positive {rate[2][0]}, negative '
            f'{rate[2][1]}); A4T2C_1 {sum(rate[1])}/256 (positive {rate[1][0]}, negative {rate[1][1]})')
    return rows, ok, note


def kmap_flips():
    """Flipped K-map entries of CAE1 / CAE2 vs the exact strict-neg Booth bit."""
    out = {}
    for name in ('cae1', 'cae2'):
        up = down = 0
        for hi, mid, lo, aj, ajm in itertools.product((0, 1), repeat=5):
            one, two = mid ^ lo, (1 - (mid ^ lo)) & (hi ^ mid)
            exact = (one & (hi ^ aj)) | (two & (hi ^ ajm))
            net = Net()
            v = net.evaluate({'x': [hi, mid, lo, aj]},
                             [cls_cells.ENCODERS[name](net, *net.bus('x', 4))], 1)[0]
            up += v > exact
            down += v < exact
        out[name] = (up, down)
    return out


def table4():
    rows = ['| Z | EV (ours) | best MSE | E[P_L given Z = 0..3] |', '|---' * 4 + '|']
    for name, (ev, mse, mean) in cls_ctm.explained_variance(4).items():
        rows.append(f'| {name} | {100 * ev:.2f} % | {mse:.2f} | {", ".join(f"{m:.2f}" for m in mean)} |')
    return rows


def _nibble(c):
    v = np.arange(-128, 128)
    a, b = np.repeat(v, 256), np.tile(v, 256)
    p = a * b
    e = (p >> 4 << 4) + cls_ctm.model(c, a, b) - p
    nz = p != 0
    return (e.mean(), np.abs(e).mean(), np.abs(e).mean() / 255 ** 2,
            (np.abs(e[nz]) / np.abs(p[nz]) <= 0.1).mean(), np.percentile(np.abs(e), 99, method='lower'))


def table5():
    rows = ['| scheme | ME | MAE | NMED (/ 255^2) | PRED@10 % | Q99 | paper ME / MAE / NMED / PRED / Q99 |',
            '|---' * 7 + '|']
    lv = (2, 6, 10)
    paper_ctm1 = {(x, y): int(cls_ctm.rule(np.int64(x + y), lv, 2, 4)) for x in range(4) for y in range(4)}
    schemes = {'Const 0000': cls_ctm.const_table(0), 'Const 0010': cls_ctm.const_table(2),
               'Const 0110': cls_ctm.const_table(6), 'CTM1': paper_ctm1,
               'CTM2': cls_ctm.ctm2_table(4), 'CTM1, CLS optimum (ours)': cls_ctm.ctm1_table(4)}
    for name, tab in schemes.items():
        me, mae, nmed, pred, q99 = _nibble(tab)
        p = TABLE5.get(name)
        rows.append(f'| {name} | {me:+.2f} | {mae:.3f} | {nmed:.3e} | {pred:.4f} | {q99:.0f} | '
                    + (' / '.join(str(x) for x in p) if p else '-') + ' |')
    return rows


def _exhaustive8(m):
    v = np.arange(-128, 128)
    a, b = np.repeat(v, 256), np.tile(v, 256)
    p = a * b
    return ErrorStats(1 << 14).add(m.products(a, b), p).result()


def table3():
    rows = ['| t | CLS levels | T1, T2 | low-bit MAE | NMED (/ 2^14) ours / paper | MRED ours / paper | bias |',
            '|---' * 7 + '|']
    for t, (pn, pm) in TABLE3.items():
        lv, t1, t2, mae, _ = cls_ctm.search(t)
        r = _exhaustive8(cls.cls(8, t, 0, 'exact', 'exact', 'ctm1', False))
        rows.append(f'| {t} | {lv} | {t1}, {t2} | {mae:.3f} | {r["NMED"]:.3e} / {pn:.2e} | '
                    f'{100 * r["MRED"]:.3f} % / {100 * pm:.2f} % | {r["bias"]:+.2f} |')
    return rows


def table67():
    rows = ['| design | NMED (/ 2^14) ours / paper | MRED ours / paper | ratio NMED, MRED | bias ours / paper | '
            'ER | max abs E |', '|---' * 7 + '|']
    for name, (pn, pm, pb) in TABLE67.items():
        r = _exhaustive8(cls.paper(name))
        rows.append(f'| {name} | {r["NMED"]:.3e} / {pn:.2e} | {100 * r["MRED"]:.2f} % / {100 * pm:.2f} % | '
                    f'{r["NMED"] / pn:.1f}, {r["MRED"] / pm:.1f} | {r["bias"]:+.2f} / '
                    f'{"-" if pb is None else pb} | {100 * r["ER"]:.2f} % | {r["max_abs"]} |')
    return rows


def search16():
    return [f'- t = {t}: levels {lv}, T1 = {t1}, T2 = {t2} (low-bit MAE {mae:.2f})'
            for t in (6, 8) for lv, t1, t2, mae, _ in [cls_ctm.search(t, 16)]]


def exhaustive16(cfgs, jobs):
    """Exhaustive 2^32-pair metrics of the 16-bit bench designs (MRED is heavy-tailed: random
    samples of 1-4 M pairs scatter by +-30 %)."""
    rows = ['| Design | ER | MAE | bias | max abs E | NMED (/ 2^30) | MRED | PRED (RED < 2 %) |',
            '|---' * 8 + '|']
    items = [(f'cls_{k}', cls.paper, (name, 16, t, w, zf)) for k, (name, t, w, zf) in cfgs.items()]
    items.append(('tacbm_12', tacbm.tacbm, (16, 12)))
    for label, builder, args in items:
        r = signed_stats(builder, 16, args, jobs=jobs)
        rows.append(f'| `{label}` | {100 * r["ER"]:.3f} % | {r["MED"]:.5g} | {r["bias"]:+.5g} | '
                    f'{r["max_abs"]} | {r["NMED"]:.4e} | {100 * r["MRED"]:.4f} % | '
                    f'{100 * r["PRED"]:.3f} % |')
        print(rows[-1], flush=True)
    return rows


def design_rows(n, cfgs):
    a, b, ap, bp = _pairs(n)
    ga, gb = _gan(n)
    v = np.arange(-(1 << (n - 1)), 1 << (n - 1))
    z = np.zeros_like(v)
    mx = 1 << (2 * n - 2)
    rows = ['| Design | t, w | ER | MAE | bias | bias b >= 0 | max abs E | NMED | MRED | a * 0 != 0 | '
            '0 * b != 0 | GAN-like bias / MAE |', '|---' * 12 + '|']
    items = [(f'cls_{k}', f'{t}, {w}', cls.paper(name, n, t, w, zf))
             for k, (name, t, w, zf) in cfgs.items()]
    if n == 16:
        items.append(('tacbm_12', '12, -', tacbm.tacbm(16, 12)))
    for label, tw, m in items:
        r = ErrorStats(mx).add(m.products(a, b), a * b).result()
        rp = ErrorStats(mx).add(m.products(ap, bp), ap * bp).result()
        rg = ErrorStats(mx).add(m.products(ga, gb), ga * gb).result()
        zb, za = int((m.products(v, z) != 0).sum()), int((m.products(z, v) != 0).sum())
        rows.append(f'| `{label}` | {tw} | {100 * r["ER"]:.2f} % | {r["MED"]:.4g} | '
                    f'{r["bias"]:+.4g} | {rp["bias"]:+.4g} | {r["max_abs"]} | {r["NMED"]:.3e} | '
                    f'{100 * r["MRED"]:.3f} % | {zb} / {v.size} | {za} / {v.size} | '
                    f'{rg["bias"]:+.4g} / {rg["MED"]:.4g} |')
        print(rows[-1], flush=True)
    return rows


def main():
    from .mulbench import WANG
    ap = argparse.ArgumentParser()
    ap.add_argument('--jobs', type=int, default=32)
    jobs = ap.parse_args().jobs
    t2, ok2, note2 = table2()
    flips = kmap_flips()
    sections = [
        ('Table II (approximate 4:2 compressors)', t2 + ['', f'All rows match the printed table: {ok2}. '
                                                         + note2 + '.']),
        ('Encoder K-map flips (32 entries, vs exact strict-neg Booth)',
         [f'- {k}: {u} entries 0 -> 1, {d} entries 1 -> 0' for k, (u, d) in flips.items()]),
        ('Table IV (2-bit CTM features, t = 4, low-bit model)', table4()),
        ('Table V (low-bit replacement model, exhaustive 8-bit)', table5()),
        ('Table III (exact encoder / compressors, CTM1 from CLS re-run per t, exhaustive 8-bit)',
         table3()),
        ('CLS at N = 16', search16()),
        ('Tables VI / VII (8-bit, exhaustive)', table67()),
        ('Bench designs, N = 16 (4 M uniform random pairs; b >= 0: 4 M pairs with b in [0, 2^15); '
         'zero checks over all 65,536 values; GAN-like: 200 k pairs of the power stimulus)',
         design_rows(16, WANG[16])),
        ('Bench designs, N = 16, exhaustive (2^32 pairs)', exhaustive16(WANG[16], jobs)),
        ('Bench designs, N = 8 (exhaustive; b >= 0 = the 32,768 pairs with b >= 0)',
         design_rows(8, WANG[8])),
    ]
    OUT.write_text('# Wang et al. 2026 (CLS truncated approximate Booth): error metrics vs the paper\n\n'
                   'Generated by `python3 -m src_gan_tsmc65.approx.paper_wang2026`. Signed operands, '
                   'b the recoded operand; NMED = MED / 2^(2N-2) unless stated.\n\n'
                   + '\n\n'.join(f'## {h}\n\n' + '\n'.join(body) for h, body in sections) + '\n')
    print(OUT)


if __name__ == '__main__':
    main()
