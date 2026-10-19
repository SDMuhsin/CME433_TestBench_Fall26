"""Quantise the float Fashion-MNIST G300 generator for a datapath width and write the chip model.

python3 -m src_gan_tsmc65.quant.build --width 16                  -> model/fmnist_w16/, rtl/cfg/w16/
python3 -m src_gan_tsmc65.quant.build --width 8 --out <dir> --header <file>   (INT8 regeneration,
                                                                    quant/check.py compares it)
Writes G300_{0,2,4}_{weight,bias}.memh, csr.memh, quant.json, latents.memh (256 benchmark latents,
seed 2000), ref_vectors/seed_0..7 and the CSR reset header g300_quant_params.vh; prints the
quality of the integer model vs the float generator on the 256 latents.
"""
import argparse
from pathlib import Path

import numpy as np

from ..common.memh import write_memh
from ..common.paths import MODEL, RTL, model_dir
from ..golden.latents import quant_z
from ..golden.model import forward
from ..golden.tanh_rom import load_rom
from ..bench.metrics import compare
from ..bench.real.sources import latents
from . import export, ptq

N_BENCH = 256


def quality(m, sz, fw, width, n=N_BENCH):
    z = latents(n)
    fpix = np.clip(np.round(ptq.float_pixels(fw, z)), 0, 255).astype(np.int64)
    ipix = forward(quant_z(z, sz, width), m)['pix'] + 128
    c = compare(ipix.astype(np.uint8), fpix.astype(np.uint8))
    return dict(bench_vs_float=dict(n=n, psnr_db=c['psnr_db'], mae=c['mae'], max_abs=c['max_abs'],
                                    bitexact_images=c['bitexact_images']))


def build(width, out, header):
    with np.load(MODEL / 'G300_float.npz') as f:
        fw = {k: f[k] for k in f.files}
    clip = ptq.CLIP_INT8 if width == 8 else ptq.CLIP_INT16
    m, sc, s = ptq.quantise_model(fw, width, clip)
    m['rom'] = load_rom()
    out.mkdir(parents=True, exist_ok=True)
    export.write_weights(out, m, width)
    export.write_csr(out, m)
    q = quality(m, sc['sZ'], fw, width)
    export.write_json(out, m, sc, clip, width, q)
    export.write_refs(out, m, sc['sZ'], width)
    write_memh(out / 'latents.memh', quant_z(latents(N_BENCH), sc['sZ'], width), bits=width)
    header.parent.mkdir(parents=True, exist_ok=True)
    export.write_header(header, m, width)
    return m, sc, q


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--width', type=int, required=True, choices=(8, 16))
    ap.add_argument('--out', type=Path)
    ap.add_argument('--header', type=Path)
    a = ap.parse_args()
    if a.width == 8 and (a.out is None or a.header is None):
        raise SystemExit('width 8: the committed model/fmnist is the reference; pass --out and --header')
    out = a.out or model_dir(a.width)
    header = a.header or RTL / 'cfg' / f'w{a.width}' / 'g300_quant_params.vh'
    m, sc, q = build(a.width, out, header)
    print(f'INT{a.width}: S = {m["S"]}, ' + ', '.join(f'{k} {m[k]}' for k in export.CSR_NAMES))
    print('scales: ' + ', '.join(f'{k} {v:.6g}' for k, v in sc.items()))
    b = q['bench_vs_float']
    print(f'vs float on {b["n"]} latents: PSNR {b["psnr_db"]:.2f} dB, MAE {b["mae"]:.3f}, max {b["max_abs"]}')
    print(f'-> {out}, {header}')


if __name__ == '__main__':
    main()
