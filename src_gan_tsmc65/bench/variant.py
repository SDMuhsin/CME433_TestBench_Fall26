"""Multiplier variant -> Verilog sources that define module gan_mul (the PE swap point) at a
datapath width W (8 | 16, docs/width16.md).

  exact            rtl/pe/gan_mul.v (the reference, any width)
  <name>           bench/variants/<name>.v or bench/variants/<name>/*.v
  mq:<name>        src_int8/bench/variants/<name>[.v] (an mq_mul8 variant of mq_chip; W = 8)
  mb:<design>      syn/mulbench/rtl/w<W>/<design>.v (a mul_core of the standalone multiplier bench)
  <path>           a .v file or a directory of .v files
The sources define gan_mul themselves or one fixed-width module that bench/adapt/ wraps:
gan_mul8 (W = 8), gan_mul16 (W = 16), mq_mul8 (W = 8, via gan_mul8), mul_core (mb:, W bits).

python3 -m src_gan_tsmc65.bench.variant [--width 8] <variant>          one source path per line
python3 -m src_gan_tsmc65.bench.variant --name <variant> [--width 8]   output-directory tag
"""
import argparse
import re
from pathlib import Path

from ..common.paths import ROOT, RTL, T65

HERE = Path(__file__).resolve().parent
ADAPT = HERE / 'adapt'
WIDTHS = (8, 16)
# fixed-width module -> (width, adapter files that turn it into gan_mul)
FIXED = {
    'gan_mul8': (8, ['gan_mul_from_gan_mul8.v']),
    'gan_mul16': (16, ['gan_mul_from_gan_mul16.v']),
    'mq_mul8': (8, ['gan_mul8_from_mq_mul8.v', 'gan_mul_from_gan_mul8.v']),
}


def _files(p):
    return [p] if p.is_file() else sorted(p.glob('*.v')) if p.is_dir() else []


def _defines(text, module):
    return re.search(rf'\bmodule\s+{module}\b', text) is not None


def _mulbench(design, width):
    f = T65 / 'syn' / 'mulbench' / 'rtl' / f'w{width}' / f'{design}.v'
    if not f.is_file():
        raise SystemExit(f'mb:{design}: no {f} (python3 -m src_gan_tsmc65.approx.mulbench --width {width})')
    if not re.search(rf'input\s+wire\s+signed\s+\[{width - 1}:0\]\s+a\b', f.read_text()):
        raise SystemExit(f'mb:{design}: not a signed {width} x {width} mul_core')
    return [f, ADAPT / 'gan_mul_from_mul_core.v']


def sources(variant, width=8):
    if width not in WIDTHS:
        raise SystemExit(f'width {width}: expected one of {WIDTHS}')
    if variant == 'exact':
        return [RTL / 'pe' / 'gan_mul.v']
    if variant.startswith('mb:'):
        return _mulbench(variant[3:], width)
    if variant.startswith('mq:'):
        base = ROOT / 'src_int8' / 'bench' / 'variants' / variant[3:]
        cands = [base.with_suffix('.v'), base]
    else:
        cands = [HERE / 'variants' / f'{variant}.v', HERE / 'variants' / variant, Path(variant)]
    for c in cands:
        fs = _files(c.resolve())
        if not fs:
            continue
        text = ''.join(f.read_text() for f in fs)
        if _defines(text, 'gan_mul'):
            return fs
        for mod, (w, adapters) in FIXED.items():
            if _defines(text, mod):
                if w != width:
                    raise SystemExit(f'{variant}: defines {mod} ({w}-bit), the chip is {width}-bit')
                return fs + [ADAPT / a for a in adapters]
        raise SystemExit(f'{variant}: defines none of gan_mul, {", ".join(FIXED)}')
    raise SystemExit(f'unknown variant {variant}')


def name(variant, width=8):
    """Short tag for output directories (width 8: the historical tags, others: _w<W> suffix)."""
    if variant[:3] in ('mq:', 'mb:'):
        base = variant[:2] + '_' + variant[3:]
    else:
        base = Path(variant.rstrip('/')).stem
    return base if width == 8 else f'{base}_w{width}'


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--name', action='store_true', help='print the output-directory tag instead')
    ap.add_argument('--width', type=int, default=8)
    ap.add_argument('variant')
    a = ap.parse_args()
    if a.name:
        print(name(a.variant, a.width))
    else:
        print('\n'.join(str(p) for p in sources(a.variant, a.width)))


if __name__ == '__main__':
    main()
