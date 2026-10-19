"""Self-check of the golden model against the reference vectors of the quantisation flow
(model/fmnist/ref_vectors/seed_*/{zq,expected}.memh).  Exit 0 only if every pixel matches.

python3 -m src_gan_tsmc65.golden.check_ref [--width 8|16]     (model/fmnist, model/fmnist_w16)
"""
import argparse
import sys

from ..common.memh import read_memh
from ..common.paths import model_dir
from .model import forward, load_model


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--width', type=int, default=8)
    mdir = model_dir(ap.parse_args().width)
    m = load_model(mdir)
    bad = 0
    seeds = sorted(mdir.glob('ref_vectors/seed_*'))
    for d in seeds:
        pix = forward(read_memh(d / 'zq.memh', bits=m['width']), m)['pix'][0]
        mism = int((pix != read_memh(d / 'expected.memh')).sum())
        bad += mism
        print(f'{d.name}: {784 - mism}/784 pixels match')
    print('PASS' if bad == 0 and seeds else 'FAIL', f'golden model vs {len(seeds)} reference vectors')
    return 0 if bad == 0 and seeds else 1


if __name__ == '__main__':
    sys.exit(main())
