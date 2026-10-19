"""Check the SDF-timed GLS products of the bench power runs against the Python models.

  python3 -m src_gan_tsmc65.approx.mulbench_gls <dir>
<dir> holds copies of the server's build/mulbench/w<N>_<design>_p2.5/pwr_<set>/p.memh as
<dir>/w<N>_<design>_<set>.memh; the operand stream is regenerated with syn/mulbench/stimulus.py
(same seed). Line k + 2 of p.memh is the product of pair k.
"""
import importlib.util
import re
import sys
from pathlib import Path

import numpy as np

from .mulbench import designs

STIM = Path(__file__).resolve().parents[1] / 'syn' / 'mulbench' / 'stimulus.py'


def _stimulus():
    spec = importlib.util.spec_from_file_location('mb_stimulus', STIM)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def check(f, stim):
    n, name, kind = re.match(r'w(\d+)_(.+)_(uniform|gan)\.memh$', f.name).groups()
    n = int(n)
    d = designs(n)[name]
    p = np.array([int(w, 16) for w in f.read_text().split()], np.int64)[2:]
    a, b = stim.stream(n, kind, d.signed, len(p))
    if d.signed:
        a, b = (np.where(v >= 1 << (n - 1), v - (1 << n), v) for v in (a, b))
        p = np.where(p >= 1 << (2 * n - 1), p - (1 << (2 * n)), p)
    same = int((d.model.products(a, b) == p).sum())
    return f'{f.stem}: {same}/{len(p)}', same == len(p)


def main():
    stim = _stimulus()
    ok = True
    for f in sorted(Path(sys.argv[1]).glob('w*.memh')):
        line, good = check(f, stim)
        ok &= good
        print(line)
    print('PASS' if ok else 'FAIL')
    raise SystemExit(0 if ok else 1)


if __name__ == '__main__':
    main()
