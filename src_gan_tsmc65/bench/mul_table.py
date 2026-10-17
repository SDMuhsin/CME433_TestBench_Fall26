"""256 x 256 product table of a gan_mul8 variant from an exhaustive iverilog run.
T[a + 128, b + 128] = gan_mul8(a, b) as a signed 16-bit value (a = weight, b = activation)."""
import subprocess
from pathlib import Path

import numpy as np

from .variant import sources

HERE = Path(__file__).resolve().parent


def mul8_table(variant, work):
    work = Path(work)
    work.mkdir(parents=True, exist_ok=True)
    img = work / 'tb_mul8_table.vvp'
    subprocess.run(['iverilog', '-g2012', '-o', str(img), str(HERE / 'tb' / 'tb_mul8_table.v'),
                    *map(str, sources(variant))], check=True)
    out = subprocess.run(['vvp', '-n', str(img)], check=True, capture_output=True, text=True).stdout
    words = [int(w, 16) for w in out.split() if len(w) == 4]
    assert len(words) == 65536, f'table has {len(words)} entries'
    t = np.array(words, np.int64).reshape(256, 256)
    return np.where(t >= 32768, t - 65536, t)
