"""python3 -m src_int8.golden.vectors <out_dir> [--params P.npz] [--story S]... [--unit-only|--chip-only]

Writes the chip vectors (plan/stream/logits/h/conv/host .memh) and the unit vectors
(lane/wb/nlu .hex) described in docs/vectors.md.
"""
import argparse
from pathlib import Path

from ..io.params import load_params
from . import chip, unit

PARAMS = Path(__file__).resolve().parents[1] / 'params' / 'mamba_e96_int8.npz'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('out', type=Path)
    ap.add_argument('--params', type=Path, default=PARAMS)
    ap.add_argument('--story', action='append', help='repeatable; default: two short stories')
    ap.add_argument('--unit-only', action='store_true')
    ap.add_argument('--chip-only', action='store_true')
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    if not a.unit_only:
        cfg, P = load_params(a.params)
        stories = [s.encode('ascii') for s in (a.story or chip.DEFAULT_STORIES)]
        vec = chip.build(cfg, P, stories)
        chip.write(a.out / 'chip', vec)
        print(f'chip: {len(vec["plan"])} tokens ({len(stories)} stories) -> {a.out / "chip"}')
    if not a.chip_only:
        (a.out / 'unit').mkdir(exist_ok=True)
        for name, n in unit.generate(a.out / 'unit').items():
            print(f'unit {name:5s} {n:8d} records')


if __name__ == '__main__':
    main()
