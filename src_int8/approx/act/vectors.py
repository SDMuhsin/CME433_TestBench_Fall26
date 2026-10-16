"""Input vectors (one "aabb" hex line per operation) for the standalone power runs, and the
checksum the gate-level testbench prints (syn/tb_mul8_power.v) for a given product table.

python3 -m src_int8.approx.act.vectors          -> build/approx/act/vec_random.hex, vec_chip.hex
  vec_random: 65,536 independent uniform (a, b) pairs (seed 1), as in the papers' power runs
  vec_chip:   65,536 consecutive input changes of mq_mul8 in the chip TB (act/dump_stream.sh),
              skipping the first 20,000 (start of the first token)
python3 -m src_int8.approx.act.vectors --checksum <table.npy> <vec.hex>   (expected GLS checksum)
"""
import argparse
import random
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
ACT = ROOT / 'build/approx/act'
NVEC, SKIP = 65536, 20000


def checksum(table, vec):
    """sum over i of (i + 1) * p_i (p as unsigned 16-bit) mod 2^32, p_i = table[a_i, b_i]"""
    s = 0
    for i, line in enumerate(Path(vec).read_text().split()):
        v = int(line, 16)
        a, b = ((v >> 8) ^ 0x80), ((v & 0xff) ^ 0x80)          # offset-binary index a + 128
        s = (s + (i + 1) * (int(table[a, b]) & 0xffff)) & 0xffffffff
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--checksum', nargs=2, metavar=('TABLE_NPY', 'VEC'))
    a = ap.parse_args()
    if a.checksum:
        print(f'{checksum(np.load(a.checksum[0]), a.checksum[1]):08x}')
        return
    ACT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(1)
    (ACT / 'vec_random.hex').write_text(''.join(f'{rng.randrange(65536):04x}\n' for _ in range(NVEC)))
    stream = (ACT / 'mul8_stream.hex').read_text().split()
    assert len(stream) >= SKIP + NVEC, 'run src_int8/approx/act/dump_stream.sh first'
    (ACT / 'vec_chip.hex').write_text('\n'.join(stream[SKIP:SKIP + NVEC]) + '\n')
    print(f'{NVEC} vectors each -> {ACT}/vec_random.hex, vec_chip.hex')


if __name__ == '__main__':
    main()
