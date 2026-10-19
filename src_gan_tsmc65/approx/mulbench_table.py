"""Hardware table of the multiplier bench from the server summaries (copied to
syn/mulbench/results/: mb_*, mbpwr_*, mbfm_*).

  python3 -m src_gan_tsmc65.approx.mulbench_table --width 16 [--tight 1.2]
Each design vs the exact design of the same signedness (u_exact / s_exact); the paper's own
savings vs its exact multiplier from approx/mulbench.py. Writes syn/mulbench/results/table_w<N>.md.
"""
import argparse
import re
from pathlib import Path

from .mulbench import designs

RES = Path(__file__).resolve().parents[1] / 'syn' / 'mulbench' / 'results'


def _num(text, pat):
    m = re.search(pat, text)
    return float(m.group(1)) if m else None


def _read(name):
    f = RES / name
    return f.read_text() if f.exists() else ''


def load(n, d, tight):
    r = {}
    for p, key in (('2.5', 'f'), ('4.0', 'r'), (tight, 't')):
        s = _read(f'mb_w{n}_{d}_p{p}.txt')
        r[key + '_area'] = _num(s, r'area_mul_um2 ([\d.]+)')
        r[key + '_wns'] = _num(s, r'setup\s+WNS\s+(-?[\d.]+)')
        r[key + '_dly'] = _num(s, r'mul_a_to_p_delay_ns (-?[\d.]+)')
        r[key + '_minp'] = _num(s, r'min_period_ns (-?[\d.]+)')
    for st in ('uniform', 'gan'):
        s = _read(f'mbpwr_w{n}_{d}_p2.5_{st}.txt')
        r[st] = _num(s, r'mul\s+internal.*total ([\d.e+-]+) W')
        r[st + '_tot'] = _num(s, r'total\s+internal.*total ([\d.e+-]+) W')
    s = _read(f'mbfm_w{n}_{d}_p2.5.txt')
    r['fm'] = 'ok' if 'SUCCEEDED' in s else ('FAIL' if s else '-')
    return r


def _cell(v, ref, fmt, scale=1.0):
    if v is None:
        return '-'
    s = f'{v * scale:{fmt}}'
    if ref and v is not None and ref is not v:
        s += f' ({100 * (v / ref - 1):+.1f} %)'
    return s


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--width', type=int, default=16, choices=(8, 16))
    ap.add_argument('--tight')
    a = ap.parse_args()
    n = a.width
    tight = a.tight or ('1.0' if n == 8 else '1.2')
    reg = designs(n)
    rows = {d: load(n, d, tight) for d in reg if (RES / f'mb_w{n}_{d}_p2.5.txt').exists()}
    head = ['| Design | mul area @2.5 ns (um^2) | mul area @4.0 ns | a->p delay @' + tight + ' ns (ns) | '
            'min period (ns) | mul power, uniform (mW) | mul power, GAN-like (mW) | energy/op uniform / GAN (pJ) | '
            'paper area / power / delay | FM |', '|---' * 10 + '|']
    out = []
    for d, r in rows.items():
        ref = rows.get('s_exact' if reg[d].signed else 'u_exact', {})
        same = ref is r
        g = (lambda k: None if same else ref.get(k))
        e = '-' if r['uniform'] is None else f"{r['uniform'] * 2.5e3:.3f} / {r['gan'] * 2.5e3:.3f}"
        pp = reg[d].paper
        out.append(f"| `{d}` | {_cell(r['f_area'], g('f_area'), '.0f')} | {_cell(r['r_area'], g('r_area'), '.0f')} | "
                   f"{_cell(r['t_dly'], g('t_dly'), '.3f')} | {_cell(r['t_minp'], g('t_minp'), '.3f')} | "
                   f"{_cell(r['uniform'], g('uniform'), '.3f', 1e3)} | {_cell(r['gan'], g('gan'), '.3f', 1e3)} | {e} | "
                   + (f'{pp[0]:+.1f} / {pp[1]:+.1f} / {pp[2]:+.1f} %' if pp else '-') + f" | {r['fm']} |")
    text = '\n'.join(head + out) + '\n'
    (RES / f'table_w{n}.md').write_text(text)
    print(text)


if __name__ == '__main__':
    main()
