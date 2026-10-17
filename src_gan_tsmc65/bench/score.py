"""Score one benchmark run: RTL pixel dumps vs the bit-exact golden model.

python3 -m src_gan_tsmc65.bench.score <variant> <run_dir> --n N
Reads <run_dir>/pix_<first>.memh (written by the chip simulations), the latents
model/fmnist/latents.memh and the int8 model; writes <run_dir>/{results.json,results.md,
rtl_u8.npy, golden_u8.npy, grid_rtl.png, grid_golden.png} and prints the summary.
Reported:
  * golden  : exact integer model of the chip (exact multiplier)  -> bit-exact images, PSNR, MAE
  * labels  : classifier/fmnist_cnn on RTL images vs on golden images -> label agreement
  * emulated: (non-exact variants) the golden model with the variant's 256 x 256 product table;
              RTL == emulation proves the run measured the multiplier, not a harness fault
"""
import argparse
import json
from pathlib import Path

import numpy as np

from ..classifier.net import CLASSES, predict
from ..common.memh import read_memh
from ..common.paths import MODEL
from ..golden.model import forward, load_model
from .images import save_grid, to_u8
from .metrics import compare
from .mul_table import mul8_table


def load_rtl(run, n):
    files = sorted(run.glob('pix_*.memh'), key=lambda p: int(p.stem.split('_')[1]))
    pix = np.concatenate([read_memh(f) for f in files]) if files else np.zeros(0, np.int64)
    if pix.size != n * 784:
        raise SystemExit(f'RTL dumps hold {pix.size} pixels, expected {n} x 784')
    return pix.reshape(n, 784)


def fmt_db(v):
    return 'inf' if v == float('inf') else f'{v:.2f}'


def report(res):
    g, lab = res['vs_golden'], res['labels']
    lines = [f"# gan65_chip benchmark: variant `{res['variant']}`, {res['n']} Fashion-MNIST latents", '',
             '| metric | value |', '|---|---|',
             f"| bit-exact images vs golden | {g['bitexact_images']}/{g['images']} |",
             f"| pixels equal to golden | {g['pixels_match']}/{g['pixels']} |",
             f"| PSNR vs golden (all pixels) | {fmt_db(g['psnr_db'])} dB |",
             f"| PSNR vs golden, worst / median image | {fmt_db(g['psnr_min_db'])} / {fmt_db(g['psnr_median_db'])} dB |",
             f"| MAE / max abs error | {g['mae']:.3f} / {g['max_abs']} grey levels |",
             f"| label agreement RTL vs golden | {lab['agree']}/{res['n']} ({100 * lab['agree'] / res['n']:.1f} %) |",
             f"| mean classifier confidence RTL / golden | {lab['conf_rtl']:.3f} / {lab['conf_golden']:.3f} |"]
    if 'vs_emulation' in res:
        e = res['vs_emulation']
        lines.append(f"| RTL vs Python emulation of the variant | {e['bitexact_images']}/{e['images']} images bit-exact |")
    lines += ['', 'Golden label histogram: ' + ', '.join(f'{c} {k}' for c, k in lab['golden_hist'].items() if k), '']
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('variant')
    ap.add_argument('run', type=Path)
    ap.add_argument('--n', type=int, required=True)
    a = ap.parse_args()
    m = load_model()
    zq = read_memh(MODEL / 'latents.memh').reshape(-1, 64)[:a.n]
    rtl = to_u8(load_rtl(a.run, a.n))
    gold = to_u8(forward(zq, m)['pix'])
    res = dict(variant=a.variant, n=a.n, vs_golden=compare(rtl, gold))
    if a.variant != 'exact':
        table = mul8_table(a.variant, a.run / 'mul_table')
        emu = to_u8(forward(zq, m, table)['pix'])
        res['vs_emulation'] = compare(rtl, emu)
        res['emulation_vs_golden'] = compare(emu, gold)
    lr, pr = predict(rtl)
    lg, pg = predict(gold)
    res['labels'] = dict(agree=int((lr == lg).sum()), conf_rtl=float(pr.max(1).mean()), conf_golden=float(pg.max(1).mean()),
                         golden_hist={c: int((lg == i).sum()) for i, c in enumerate(CLASSES)})
    np.save(a.run / 'rtl_u8.npy', rtl.reshape(-1, 28, 28))
    np.save(a.run / 'golden_u8.npy', gold.reshape(-1, 28, 28))
    save_grid(a.run / 'grid_rtl.png', rtl[:64])
    save_grid(a.run / 'grid_golden.png', gold[:64])
    (a.run / 'results.json').write_text(json.dumps(res, indent=1) + '\n')
    md = report(res)
    (a.run / 'results.md').write_text(md)
    print(md)


if __name__ == '__main__':
    main()
