"""Fast software screen of a mq_mul8 variant on the benchmark crops (minutes, not the headline).

python3 -m src_int8.bench.emu.run <variant> <bench_dir> [--n N] [--rtl <run_dir>]
Writes build/bench/emu/<variant>_<bench>/{logits.npy, nll.npy, summary.json}; prints BPB vs the
exact golden on the same crops (paired) and, with --rtl, the logit agreement with an RTL run.
"""
import argparse
import json
import time
from pathlib import Path

import numpy as np

from ...golden.io.params import load_params
from ...golden.model import HwModel
from ..common import PARAMS, nll_bits
from ..stats import paired, summary
from .model import approx
from .table import mul8_table


def emu_dir(bench, name, n, length):
    return Path(bench).parent / 'emu' / f'{name}_c{n}x{length}'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('variant')
    ap.add_argument('bench', type=Path)
    ap.add_argument('--n', type=int)
    ap.add_argument('--rtl', type=Path)
    a = ap.parse_args()
    name = Path(a.variant).stem
    segs = np.load(a.bench / 'crops.npy')[:a.n]
    n, L = segs.shape[0], segs.shape[1] - 1
    out = emu_dir(a.bench, name, n, L)
    out.mkdir(parents=True, exist_ok=True)
    table = mul8_table(a.variant, out)
    exact = np.arange(-128, 128)[:, None] * np.arange(-128, 128)[None, :]
    cfg, P = load_params(PARAMS)
    model, t0 = HwModel(cfg, P, batch=n), time.time()
    logits = np.empty((n, L, cfg['vocab']), np.int16)
    with approx(table):
        for t in range(L):
            logits[:, t] = model.step(segs[:, t])
    nll = np.stack([nll_bits(logits[i], segs[i]) for i in range(n)])
    np.save(out / 'logits.npy', logits)
    np.save(out / 'nll.npy', nll)
    res = dict(variant=name, source='emulator (golden + mul8 table)', wall_s=time.time() - t0,
               table_entries_differing_from_exact=int((table != exact).sum()),
               table_max_abs_error=int(np.abs(table - exact).max()), **summary(nll))
    ref = a.bench / 'ref' / 'nll.npy'
    if ref.exists():
        res['vs_exact_golden'] = paired(nll, np.load(ref)[:n])
    if a.rtl:
        have = [i for i in range(n) if (a.rtl / 'logits' / f'crop_{i:04d}.npy').exists()]
        bad = sum(int((np.load(a.rtl / 'logits' / f'crop_{i:04d}.npy') != logits[i]).any(-1).sum())
                  for i in have)
        res['vs_rtl'] = dict(run=str(a.rtl), crops_compared=len(have), tokens_with_logit_mismatch=bad)
    (out / 'summary.json').write_text(json.dumps(res, indent=1) + '\n')
    print(json.dumps(res, indent=1))


if __name__ == '__main__':
    main()
