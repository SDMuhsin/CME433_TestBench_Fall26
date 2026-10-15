"""Decay-path accuracy of the Q0.15 dA (spec section 2, 5.1): exhaustive over every exp2 input
on a 2^-13 grid of p (Q11.19 >> 6) plus the dead-band check of the INT24 state.

  python3 -m src_int8.longctx.decay [--hist results.npz]
"""
import argparse

import numpy as np

from ..golden.ops.formats import rsh, sat
from ..golden.ops.nlu import exp2

LN2 = np.log(2)


def decay_table(p_hist=None, hist_bits=6):
    """Rows per true-tau range: max abs err of dA in Q0.15 LSB, max / mean rel err of (1 - dA),
    codes saturated at 1 - 2^-15, usage share from a long_eval histogram."""
    p = -np.arange(1, 16 * 2 ** 19, 64, dtype=np.int64)                 # every 2^-13 of p
    dA = exp2(p) / 2 ** 15
    exact = np.exp2(p / 2 ** 19)
    tau = -1 / np.log(exact)
    abs_lsb = np.abs(dA - exact) * 2 ** 15
    rel1 = np.abs((1 - dA) - (1 - exact)) / (1 - exact)
    mean1 = ((1 - dA) - (1 - exact)) / (1 - exact)
    frozen = dA >= 32767 / 2 ** 15
    rows = []
    for lo, hi in ((0, 1), (1, 10), (10, 100), (100, 1000), (1000, 10000), (10000, 100000), (100000, np.inf)):
        m = (tau >= lo) & (tau < hi)
        if not m.any():
            continue
        usage = None
        if p_hist is not None and (-p[m]).min() >= (1 << (19 - hist_bits)):     # row resolved by the bins
            idx = np.unique(np.clip((-p[m]) >> (19 - hist_bits), 0, len(p_hist) - 1))
            usage = p_hist[idx].sum() / max(p_hist.sum(), 1)
        rows.append(dict(lo=lo, hi=hi, codes=int(m.sum()), abs_lsb=abs_lsb[m].max(), rel1=rel1[m].max(),
                         mean1=mean1[m].mean(), frozen=int(frozen[m].sum()), usage=usage))
    first_frozen = -p[frozen].min() / 2 ** 19 if frozen.any() else None
    return rows, first_frozen


def dead_band(tau_list=(10, 30, 100, 300, 1000, 3000, 10000, 30000), starts=97):
    """Free decay of the INT24 state h <- sat24(rsh(h * dA, 15)): steps to reach 1/e of the start."""
    out = []
    for tau in tau_list:
        p = np.int64(round(-2 ** 19 / (tau * LN2)))
        dA = int(exp2(np.array([p]))[0])
        h0 = np.linspace(0.01, 17.0, starts) * 2 ** 17
        h = h0.astype(np.int64)
        steps = np.full(starts, -1)
        for t in range(1, 40000):
            h = sat(rsh(h * dA, 15), 24)
            done = (steps < 0) & (h <= h0 / np.e)
            steps[done] = t
            if (steps >= 0).all():
                break
        ok = steps[steps >= 0]
        out.append((tau, dA / 2 ** 15, (int(ok.min()), int(np.median(ok)), int(ok.max())) if len(ok) else None,
                    int((steps < 0).sum())))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--hist', help='long_eval .npz with p_hist for the usage column')
    a = ap.parse_args()
    p_hist, bits = None, 6
    if a.hist:
        r = np.load(a.hist)
        p_hist, bits = r['p_hist'], int(r['p_hist_bits']) if 'p_hist_bits' in r.files else 6
    rows, first_frozen = decay_table(p_hist, bits)
    print(f'dA saturates at 1 - 2^-15 (effective tau 32768) for |p| <= {first_frozen:.3e} '
          f'(true tau >= {-1 / np.log(np.exp2(-first_frozen)):.0f} tokens)')
    print('tau range [tokens]   codes  max|dA err| LSB  max|rel(1-dA)|  mean rel(1-dA)  sat@1-2^-15  usage')
    for r in rows:
        usage = f'{r["usage"]:.2e}' if r['usage'] is not None else '-'
        print(f'[{r["lo"]:>6.0f}, {r["hi"]:>7.0f})  {r["codes"]:6d}  {r["abs_lsb"]:11.2f}      {r["rel1"]:.2e}      '
              f'{r["mean1"]:+.2e}  {r["frozen"]:11d}  {usage}')
    if p_hist is not None:
        print(f'usage: share of decay evaluations with |p| < 2^-{bits} (tau > {1 / (2.0 ** -bits * LN2):.0f}): '
              f'{p_hist[0] / p_hist.sum():.3f}; with p <= -16 (dA = 0): {p_hist[-1] / p_hist.sum():.4f}; '
              f'rows below the bin resolution show "-"')
    print('free decay of the INT24 state, steps to 1/e:  tau  dA(hw)  min / median / max  (stuck)')
    for tau, dA, s, stuck in dead_band():
        rng = f'{s[0]:6d} / {s[1]:6d} / {s[2]:6d}' if s else '     - /      - /      -'
        print(f'  {tau:6d}  {dA:.6f}  {rng}  ({stuck}/97 never reach 1/e)')


if __name__ == '__main__':
    main()
