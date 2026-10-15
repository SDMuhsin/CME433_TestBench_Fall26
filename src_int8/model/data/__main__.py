"""python3 -m src_int8.model.data <TinyStories.txt> <out.bin>: build a byte corpus file."""
import argparse
from pathlib import Path

from .corpus import build_bin


def main():
    ap = argparse.ArgumentParser(description=build_bin.__doc__)
    ap.add_argument('src', type=Path)
    ap.add_argument('dst', type=Path)
    a = ap.parse_args()
    build_bin(a.src, a.dst)


if __name__ == '__main__':
    main()
