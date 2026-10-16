"""256 x 256 product table of a mq_mul8 variant, from an exhaustive iverilog run of its Verilog."""
import subprocess
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
SRC = HERE.parents[1]


def variant_sources(variant):
    """Same resolution as bench/build.sh."""
    if variant == 'exact':
        return [SRC / 'rtl/int/mq_mul8.v']
    for p in (SRC / f'bench/variants/{variant}.v', Path(variant)):
        if p.is_file():
            return [p]
    for d in (SRC / f'bench/variants/{variant}', Path(variant)):
        if d.is_dir():
            return sorted(d.glob('*.v'))
    raise SystemExit(f'unknown variant {variant}')


def mul8_table(variant, work):
    """-> int64 [256, 256], T[a + 128, b + 128] = mq_mul8(a, b) as a signed 16-bit value."""
    work = Path(work)
    work.mkdir(parents=True, exist_ok=True)
    img = work / 'tb_mul8_table.vvp'
    subprocess.run(['iverilog', '-g2012', '-o', str(img), str(HERE / 'tb_mul8_table.v'),
                    *map(str, variant_sources(variant))], check=True)
    out = subprocess.run(['vvp', '-n', str(img)], check=True, capture_output=True, text=True).stdout
    words = [int(w, 16) for w in out.split() if len(w) == 4]
    assert len(words) == 65536, f'table has {len(words)} entries'
    t = np.array(words, np.int64).reshape(256, 256)
    return np.where(t >= 32768, t - 65536, t)
