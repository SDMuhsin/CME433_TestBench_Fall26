"""One RTL worker: drives one Verilator chip simulation over a list of crops, state reset per crop.

python3 -m src_int8.bench.worker <sim> <bench_dir> <run_dir> --worker W --jobs J
Crops i with i % J == W are run in order; crop i's 128 INT16 logits per token are written to
<run_dir>/logits/crop_<i>.npy (int16 [L, 128]) with its cycle counts in crop_<i>.json; existing
crops are skipped, so an interrupted run resumes. Python only feeds bytes and collects logits.
"""
import argparse
import json
import time
from pathlib import Path

import numpy as np

from ..demo.host.chip_link import ChipSim


def run_crop(chip, seg):
    L = len(seg) - 1
    logits, done, errors = np.empty((L, 128), np.int16), set(), 0
    for t in range(L):
        z, cyc = chip.step(int(seg[t]), reset=t == 0)
        logits[t] = z
        done.add(cyc['done'])
        errors += cyc['errors']
    return logits, dict(done_clk=sorted(done), tb_errors=errors)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('sim')
    ap.add_argument('bench', type=Path)
    ap.add_argument('run', type=Path)
    ap.add_argument('--worker', type=int, required=True)
    ap.add_argument('--jobs', type=int, required=True)
    a = ap.parse_args()
    segs = np.load(a.bench / 'crops.npy')
    out = a.run / 'logits'
    out.mkdir(parents=True, exist_ok=True)
    todo = [i for i in range(a.worker, len(segs), a.jobs) if not (out / f'crop_{i:04d}.npy').exists()]
    if not todo:
        return 0
    tab = a.bench / 'tables'
    work = a.run / 'work' / f'w{a.worker:02d}'
    chip = ChipSim(a.sim, tab / 'base.memh', tab / 'emb.memh', work, work / 'sim.log')
    for i in todo:
        t0 = time.time()
        logits, info = run_crop(chip, segs[i])
        np.save(out / f'crop_{i:04d}.tmp.npy', logits)
        (out / f'crop_{i:04d}.tmp.npy').rename(out / f'crop_{i:04d}.npy')
        (out / f'crop_{i:04d}.json').write_text(json.dumps(dict(info, wall_s=time.time() - t0)))
        print(f'crop {i}: {len(logits)} tokens, {time.time() - t0:.0f} s', flush=True)
    tb_errors = chip.close()
    print(f'worker {a.worker} done, TB errors {tb_errors}', flush=True)
    return 0 if tb_errors == 0 else 1


if __name__ == '__main__':
    raise SystemExit(main())
