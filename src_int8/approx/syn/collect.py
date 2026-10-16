"""Tables of the standalone mq_mul8 runs from the summary files (after syn/sync.sh pull).

python3 src_int8/approx/syn/collect.py [--corner tt] [--delay 4.0] [--base exact]
  sweep : area / achieved critical delay per variant and max-delay target, every corner found
  point : one DC point (corner, target): area, delay, power with chip and random vectors,
          energy per op, PDP (power x critical delay) and changes vs the baseline variant
Reads build/approx/summary/syn_<tag>.txt and pwr_<tag>_<vec>.txt; prints Markdown.
"""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SUM = ROOT / 'build/approx/summary'
TAG = re.compile(r'^syn_(?P<v>.+)_(?P<c>ss|tt|ff)_d(?P<d>[0-9.]+)$')


def fields(path):
    """'key value ...' lines -> {key: float of the first number after it}"""
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r'^\s*(\w+)\s+(-?[0-9.]+(?:e[-+]?\d+)?)', line)
        if m:
            out.setdefault(m.group(1), float(m.group(2)))
    return out


def load():
    syn = {}
    for f in SUM.glob('syn_*.txt'):
        m = TAG.match(f.stem)
        if m:
            syn[(m['v'], m['c'], m['d'])] = fields(f)
    return syn


def power(v, c, d, vec):
    f = SUM / f'pwr_{v}_{c}_d{d}_{vec}.txt'
    return fields(f) if f.exists() else None


def sweep(syn, corner):
    vs = sorted({k[0] for k in syn if k[1] == corner})
    ds = sorted({k[2] for k in syn if k[1] == corner}, key=float)
    print(f'\n### Area um2 / critical delay ns, corner {corner}\n')
    print('| variant | ' + ' | '.join(f'{d} ns' for d in ds) + ' |')
    print('|---|' + '---:|' * len(ds))
    for v in vs:
        cells = [f"{s['cell_area_um2']:.0f} / {s['critical_delay_ns']:.2f}" if (s := syn.get((v, corner, d))) else ''
                 for d in ds]
        print(f'| {v} | ' + ' | '.join(cells) + ' |')


def pct(x, b):
    return f'{100 * (x / b - 1):+.1f} %'


def point(syn, corner, d, base):
    rows = []
    for (v, c, dd), s in sorted(syn.items()):
        if c != corner or dd != d:
            continue
        pc, pr = power(v, c, d, 'chip'), power(v, c, d, 'random')
        rows.append((v, s, pc, pr, power(v, c, d, 'chip_zd')))
    ref = {r[0]: r for r in rows}.get(base)
    print(f'\n### Point {corner}, max delay {d} ns (power: chip / random vectors, uW; PDP with chip vectors;'
          ' zd: zero-delay simulation, no glitches)\n')
    print('| variant | area um2 | delay ns | P chip uW | P random uW | E/op chip pJ | PDP chip fJ |'
          ' area vs base | P chip vs base | P random vs base | PDP vs base | P chip zd uW | zd vs base |')
    print('|---|' + '---:|' * 12)
    P = lambda p: p['total_power'] * 1e6 if p else float('nan')
    for v, s, pc, pr, pz in rows:
        a, t = s['cell_area_um2'], s['critical_delay_ns']
        pdp = P(pc) * t
        line = [v, f'{a:.0f}', f'{t:.3f}', f'{P(pc):.1f}', f'{P(pr):.1f}',
                f"{pc['energy_per_op_pJ']:.3f}" if pc else '', f'{pdp:.1f}']
        if ref:
            ra, rt, rc, rr = ref[1]['cell_area_um2'], ref[1]['critical_delay_ns'], P(ref[2]), P(ref[3])
            line += [pct(a, ra), pct(P(pc), rc), pct(P(pr), rr), pct(pdp, rc * rt), f'{P(pz):.1f}', pct(P(pz), P(ref[4]))]
        print('| ' + ' | '.join(line) + ' |')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--corner', default='tt')
    ap.add_argument('--delay', action='append', help='DC target(s) of the point table (default 4.0)')
    ap.add_argument('--base', default='exact')
    a = ap.parse_args()
    syn = load()
    for c in sorted({k[1] for k in syn}):
        sweep(syn, c)
    for d in a.delay or ['4.0']:
        point(syn, a.corner, d, a.base)


if __name__ == '__main__':
    main()
