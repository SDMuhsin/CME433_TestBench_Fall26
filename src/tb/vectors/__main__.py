"""Generate all unit-test vectors: python3 -m src.tb.vectors <out_dir>."""
import sys
from pathlib import Path

from . import fpu, lane, nlu, wb


def main(out):
    out.mkdir(parents=True, exist_ok=True)
    for mod in (fpu, wb, lane, nlu):
        for name, n in mod.generate(out).items():
            print(f'vectors {name:14s} {n:8d}')


if __name__ == '__main__':
    main(Path(sys.argv[1]))
