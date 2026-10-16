"""Prepare the benchmark inputs: crops.npy and the chip's stream / embedding tables.

python3 -m src_int8.bench.prep <val.bin> <bench_dir> --n 256 --length 1024
"""
import argparse
import json
from pathlib import Path

import numpy as np

from ..demo.host.chip_link import write_stream_tables
from ..golden.io.params import load_params
from .common import PARAMS, SEED, crops


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('val_bin')
    ap.add_argument('out', type=Path)
    ap.add_argument('--n', type=int, default=256)
    ap.add_argument('--length', type=int, default=1024)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    segs = crops(a.val_bin, a.n, a.length)
    np.save(a.out / 'crops.npy', segs)
    _, P = load_params(PARAMS)
    write_stream_tables(P, a.out / 'tables')
    meta = dict(val_bin=str(a.val_bin), n=a.n, length=a.length, seed=SEED, params=PARAMS,
                predicted_bytes=a.n * a.length)
    (a.out / 'crops.json').write_text(json.dumps(meta, indent=1) + '\n')
    print(f'{a.n} crops x {a.length} predicted bytes -> {a.out}/crops.npy')


if __name__ == '__main__':
    main()
