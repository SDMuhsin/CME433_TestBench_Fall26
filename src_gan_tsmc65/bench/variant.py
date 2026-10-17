"""Multiplier variant -> Verilog sources that define module gan_mul8.

  exact            rtl/pe/gan_mul8.v (the reference)
  <name>           bench/variants/<name>.v or bench/variants/<name>/*.v
  mq:<name>        src_int8/bench/variants/<name>[.v] (an mq_mul8 variant of mq_chip)
  <path>           a .v file or a directory of .v files
A variant that defines mq_mul8 instead of gan_mul8 gets bench/adapt/gan_mul8_from_mq_mul8.v.

python3 -m src_gan_tsmc65.bench.variant <variant>     prints one source path per line
"""
import re
import sys
from pathlib import Path

from ..common.paths import ROOT, RTL, T65

HERE = Path(__file__).resolve().parent


def _files(p):
    return [p] if p.is_file() else sorted(p.glob('*.v')) if p.is_dir() else []


def sources(variant):
    if variant == 'exact':
        return [RTL / 'pe' / 'gan_mul8.v']
    if variant.startswith('mq:'):
        base = ROOT / 'src_int8' / 'bench' / 'variants' / variant[3:]
        cands = [base.with_suffix('.v'), base]
    else:
        cands = [HERE / 'variants' / f'{variant}.v', HERE / 'variants' / variant, Path(variant)]
    for c in cands:
        fs = _files(c.resolve())
        if fs:
            text = ''.join(f.read_text() for f in fs)
            if not re.search(r'\bmodule\s+gan_mul8\b', text):
                if not re.search(r'\bmodule\s+mq_mul8\b', text):
                    raise SystemExit(f'{variant}: defines neither gan_mul8 nor mq_mul8')
                fs.append(HERE / 'adapt' / 'gan_mul8_from_mq_mul8.v')
            return fs
    raise SystemExit(f'unknown variant {variant}')


def name(variant):
    """Short tag for output directories."""
    return 'mq_' + variant[3:] if variant.startswith('mq:') else Path(variant.rstrip('/')).stem


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--name':
        print(name(sys.argv[2]))
    else:
        print('\n'.join(str(p) for p in sources(sys.argv[1])))
