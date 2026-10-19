"""Check that quant/ptq.py is the scheme of the committed INT8 model: rebuild INT8 into <dir> and
compare every integer asset with model/fmnist and the CSR constants with its quant.json.

python3 -m src_gan_tsmc65.quant.check [--dir build/gan65/quant/w8]
"""
import argparse
import filecmp
import json
import sys
from pathlib import Path

from ..common.paths import BUILD, MODEL
from .build import build

FILES = [f'G300_{n}_{t}.memh' for n in (0, 2, 4) for t in ('weight', 'bias')] + ['latents.memh'] + \
        [f'ref_vectors/seed_{s}/{f}.memh' for s in range(8) for f in ('zq', 'expected')]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--dir', type=Path, default=BUILD / 'quant' / 'w8')
    a = ap.parse_args()
    m, sc, _ = build(8, a.dir, a.dir / 'g300_quant_params.vh')
    bad = [f for f in FILES if not filecmp.cmp(a.dir / f, MODEL / f, shallow=False)]
    ref = json.loads((MODEL / 'quant.json').read_text())
    bad += [k for k, v in ref['csr'].items() if v['value'] != m[k]]
    bad += [k for k in ('sZ', 'sH0', 'sH2') if abs(sc[k] / ref['calibration'][k] - 1) > 1e-12]
    bad += [k for k, v in ref['scales'].items() if abs(sc[k] / v - 1) > 1e-7]
    print(f'{len(FILES)} files, 6 CSRs, 9 scales vs model/fmnist:', 'PASS' if not bad else f'FAIL {bad}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
