"""Compare the pixels of a gate-level run with the golden model emulating the same multiplier.

python3 -m src_gan_tsmc65.sim.gls.check_pix <variant> <pix.memh> [seed=0] [--width 8|16]

run_gls.csh only checks against the exact-multiplier golden pixels; for an approximate
variant this shows that the netlist matches the variant's own integer model (bit-exact).
--width 16 uses model/fmnist_w16 and the 16-bit model of bench/mul_model.py (mb:<design>).
"""
import argparse
import tempfile

from ...bench.mul_model import mul_model
from ...common.memh import read_memh
from ...common.paths import model_dir
from ...golden.model import forward, load_model


def main(variant, pix_file, seed=0, width=8):
    mdir = model_dir(width)
    zq = read_memh(mdir / f'ref_vectors/seed_{seed}/zq.memh', bits=width)
    with tempfile.TemporaryDirectory() as work:
        mul = mul_model(variant, width, work)
        if mul is None and variant != 'exact':
            raise SystemExit(f'no {width}-bit emulation model for {variant}')
        want = forward(zq, load_model(mdir), mul)['pix'][0]
    got = read_memh(pix_file)
    mism = int((got != want).sum())
    print(f'{"PASS" if mism == 0 else "FAIL"} {variant} seed_{seed}: {784 - mism}/784 pixels match the emulation')
    return 0 if mism == 0 else 1


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('variant')
    ap.add_argument('pix')
    ap.add_argument('seed', nargs='?', type=int, default=0)
    ap.add_argument('--width', type=int, default=8)
    a = ap.parse_args()
    raise SystemExit(main(a.variant, a.pix, a.seed, a.width))
