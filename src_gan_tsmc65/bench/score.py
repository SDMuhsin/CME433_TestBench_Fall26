"""Score one benchmark run: RTL pixel dumps vs the bit-exact golden model.

python3 -m src_gan_tsmc65.bench.score <variant> <run_dir> --n N [--width 8|16] [--zq latents.memh]
Reads <run_dir>/pix_<first>.memh (written by the chip simulations), the latents
(default <model>/latents.memh) and the integer model of the width (model/fmnist, model/fmnist_w16); writes <run_dir>/{results.json,results.md,
rtl_u8.npy, golden_u8.npy, grid_rtl.png, grid_golden.png} and prints the summary.
Reported:
  * golden  : exact integer model of the chip (exact multiplier)  -> bit-exact images, PSNR, MAE
  * labels  : classifier/fmnist_cnn on RTL images vs on golden images -> label agreement
  * float   : RTL images vs the float generator on the same (unquantised) latents: PSNR, labels
  * emulated: (non-exact variants) the golden model with the variant's multiplier model
              (bench/mul_model.py: 8-bit product table, 16-bit mb: numpy model);
              RTL == emulation proves the run measured the multiplier, not a harness fault
"""
import argparse
import json
from pathlib import Path

import numpy as np

from ..classifier.net import CLASSES, predict
from ..common.memh import read_memh
from ..common.paths import model_dir
from ..golden.model import forward, load_model
from .images import save_grid, to_u8
from .metrics import compare
from .mul_model import mul_model
from .real.sources import float_gen


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
    wd = '' if res.get('width', 8) == 8 else f", {res['width']}-bit datapath"
    lines = [f"# gan65_chip benchmark: variant `{res['variant']}`{wd}, {res['n']} Fashion-MNIST latents", '',
             '| metric | value |', '|---|---|',
             f"| bit-exact images vs golden | {g['bitexact_images']}/{g['images']} |",
             f"| pixels equal to golden | {g['pixels_match']}/{g['pixels']} |",
             f"| PSNR vs golden (all pixels) | {fmt_db(g['psnr_db'])} dB |",
             f"| PSNR vs golden, worst / median image | {fmt_db(g['psnr_min_db'])} / {fmt_db(g['psnr_median_db'])} dB |",
             f"| MAE / max abs error | {g['mae']:.3f} / {g['max_abs']} grey levels |",
             f"| label agreement RTL vs golden | {lab['agree']}/{res['n']} ({100 * lab['agree'] / res['n']:.1f} %) |",
             f"| mean classifier confidence RTL / golden | {lab['conf_rtl']:.3f} / {lab['conf_golden']:.3f} |",
             f"| PSNR / MAE vs float generator | {fmt_db(res['vs_float']['psnr_db'])} dB / {res['vs_float']['mae']:.3f} |",
             f"| label agreement RTL vs float generator | {lab['agree_float']}/{res['n']} "
             f"({100 * lab['agree_float'] / res['n']:.1f} %) |"]
    if 'vs_emulation' in res:
        e = res['vs_emulation']
        lines.append(f"| RTL vs Python emulation of the variant | {e['bitexact_images']}/{e['images']} images bit-exact |")
    elif res['variant'] != 'exact':
        lines.append('| RTL vs Python emulation of the variant | n/a (no Python model of this variant) |')
    lines += ['', 'Golden label histogram: ' + ', '.join(f'{c} {k}' for c, k in lab['golden_hist'].items() if k), '']
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('variant')
    ap.add_argument('run', type=Path)
    ap.add_argument('--n', type=int, required=True)
    ap.add_argument('--width', type=int, default=8)
    ap.add_argument('--zq', type=Path)
    a = ap.parse_args()
    mdir = model_dir(a.width)
    m = load_model(mdir)
    zq = read_memh(a.zq or mdir / 'latents.memh', bits=a.width).reshape(-1, 64)[:a.n]
    rtl = to_u8(load_rtl(a.run, a.n))
    gold = to_u8(forward(zq, m)['pix'])
    res = dict(variant=a.variant, width=a.width, n=a.n, vs_golden=compare(rtl, gold))
    mul = mul_model(a.variant, a.width, a.run / 'mul_table')
    if mul is not None:
        emu = to_u8(forward(zq, m, mul)['pix'])
        res['vs_emulation'] = compare(rtl, emu)
        res['emulation_vs_golden'] = compare(emu, gold)
    flt = float_gen(a.n).reshape(a.n, 784)
    res['vs_float'] = compare(rtl, flt)
    lr, pr = predict(rtl)
    lg, pg = predict(gold)
    lf, _ = predict(flt)
    res['labels'] = dict(agree=int((lr == lg).sum()), agree_float=int((lr == lf).sum()), conf_rtl=float(pr.max(1).mean()), conf_golden=float(pg.max(1).mean()),
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
