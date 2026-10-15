"""Bucket table from a `long_eval` .npz: BPB golden (and fake-quant) vs float by position, state health.

Delta is the paired golden - float BPB on the same crops; +-1.96 SE is over crops.
  python3 -m src_int8.longctx.report results.npz [--md]
"""
import argparse

import numpy as np

EDGES = (0, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768)


def buckets(L):
    e = [x for x in EDGES if x < L] + [L]
    return list(zip(e[:-1], e[1:]))


def table(r):
    ng, nf, st = r['nll_golden'], r['nll_float'], r['stats']
    nq = r['nll_fakeq'] if 'nll_fakeq' in r.files else None
    rows = []
    for lo, hi in buckets(ng.shape[1]):
        g = ng[:, lo:hi].mean(1) / np.log(2)
        f = nf[:, lo:hi].mean(1) / np.log(2)
        d = g - f
        se = 1.96 * d.std(ddof=1) / np.sqrt(len(d))
        s = st[lo:hi]                                   # [t, layer, (gmax, fmax, sat, frozen, err)]
        rows.append(dict(lo=lo, hi=hi, golden=g.mean(), float=f.mean(), delta=d.mean(), ci=se,
                         rel=d.mean() / f.mean(), hmax=s[:, :, 0].max(), hmax_f=s[:, :, 1].max(),
                         sat=int(s[:, :, 2].sum()), frozen=s[:, :, 3].mean(), err=s[:, :, 4].mean(),
                         fakeq=(nq[:, lo:hi].mean() / np.log(2)) if nq is not None else None))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('npz')
    ap.add_argument('--md', action='store_true', help='markdown table')
    a = ap.parse_args()
    r = np.load(a.npz)
    n, L = r['nll_golden'].shape
    rows = table(r)
    allg, allf = r['nll_golden'].mean() / np.log(2), r['nll_float'].mean() / np.log(2)
    extra = f' fake-quant {r["nll_fakeq"].mean() / np.log(2):.4f}' if 'nll_fakeq' in r.files else ''
    print(f'{n} crops x {L} bytes, state carried; overall golden {allg:.4f} float {allf:.4f} '
          f'({(allg - allf) / allf * 100:+.3f} %){extra}')
    hdr = ['positions', 'golden BPB'] + (['fake-quant BPB'] if rows[0]['fakeq'] is not None else []) + \
          ['float BPB', 'delta (95% CI)', 'rel', 'max abs h hw / float', 'sat INT24', 'dA==1 frac', 'rel state err']

    def fmt(x):
        cells = [f'[{x["lo"]}, {x["hi"]})', f'{x["golden"]:.4f}']
        if x['fakeq'] is not None:
            cells.append(f'{x["fakeq"]:.4f}')
        return cells + [f'{x["float"]:.4f}', f'{x["delta"]:+.4f} +- {x["ci"]:.4f}', f'{x["rel"] * 100:+.3f} %',
                        f'{x["hmax"]:.1f} / {x["hmax_f"]:.1f}', f'{x["sat"]}', f'{x["frozen"]:.2e}', f'{x["err"]:.4f}']
    if a.md:
        print('| ' + ' | '.join(hdr) + ' |\n|' + '---|' * len(hdr))
        for x in rows:
            print('| ' + ' | '.join(fmt(x)) + ' |')
    else:
        for x in [None] + rows:
            print('  '.join(f'{c:>20s}' for c in (hdr if x is None else fmt(x))))


if __name__ == '__main__':
    main()
