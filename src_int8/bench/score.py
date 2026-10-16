"""Score an RTL benchmark run: BPB / PPL from the chip's logits, vs the Python golden and a baseline.

python3 -m src_int8.bench.score <bench_dir> <run_dir> [--baseline <run_dir>] [--variant name]
Reads <run_dir>/logits/crop_*.npy (written by the RTL workers) and, if present, <bench_dir>/ref/
(golden logits) and <run_dir>/wall.json; writes <run_dir>/nll.npy, results.json, results.md.
"""
import argparse
import json
import os
from pathlib import Path

import numpy as np

from .common import nll_bits
from .emu.run import emu_dir
from .stats import paired, summary

HEADS = (256, 512)  # prefix subsets; the first 256 crops are those of the 1.3749 golden number


def load_run(bench, run):
    segs = np.load(bench / 'crops.npy')
    n = len(segs)
    missing = [i for i in range(n) if not (run / 'logits' / f'crop_{i:04d}.npy').exists()]
    if missing:
        raise SystemExit(f'{len(missing)} crop(s) missing in {run}/logits, first {missing[0]}')
    logits = np.stack([np.load(run / 'logits' / f'crop_{i:04d}.npy') for i in range(n)])
    info = [json.loads((run / 'logits' / f'crop_{i:04d}.json').read_text()) for i in range(n)]
    return segs, logits, info


def score(bench, run, baseline=None, variant=None):
    segs, logits, info = load_run(bench, run)
    nll = np.stack([nll_bits(logits[i], segs[i]) for i in range(len(segs))])
    np.save(run / 'nll.npy', nll)
    res = dict(variant=variant or run.name, source='RTL (Verilator, tb_mq_demo)', **summary(nll))
    for k in HEADS:
        if len(segs) > k:
            res[f'head{k}'] = summary(nll[:k])
    res['done_clk'] = sorted({c for r in info for c in r['done_clk']})
    res['tb_errors'] = int(sum(r['tb_errors'] for r in info))
    if (run / 'wall.json').exists():
        res.update(json.loads((run / 'wall.json').read_text()))
    ref = bench / 'ref'
    if (ref / 'logits.npy').exists():
        rl, rn = np.load(ref / 'logits.npy', mmap_mode='r'), np.load(ref / 'nll.npy')
        diff = (logits != rl).any(-1)
        res['golden'] = dict(summary(rn), tokens_with_logit_mismatch=int(diff.sum()),
                             logit_mismatch_frac=float((logits != rl).mean()),
                             bit_exact=bool(not diff.any()), **paired(nll, rn))
        for k in HEADS:
            if len(segs) > k:
                res['golden'][f'head{k}_bpb'] = float(rn[:k].mean())
    emu = emu_dir(bench, res['variant'], *logits.shape[:2])
    if (emu / 'logits.npy').exists():
        el, en = np.load(emu / 'logits.npy', mmap_mode='r'), np.load(emu / 'nll.npy')
        if el.shape == logits.shape:
            diff = (logits != el).any(-1)
            res['emulator'] = dict(dir=os.path.relpath(emu), bpb=float(en.mean()), bit_exact=bool(not diff.any()),
                                   tokens_with_logit_mismatch=int(diff.sum()))
    if baseline is not None:
        bn = np.load(baseline / 'nll.npy')
        res['vs_baseline'] = dict(baseline=os.path.relpath(baseline), **paired(nll, bn))
    (run / 'results.json').write_text(json.dumps(res, indent=1) + '\n')
    (run / 'results.md').write_text(markdown(res))
    return res


def markdown(r):
    f = lambda s: f"{s['bpb']:.4f} +- {s['bpb_se']:.4f} (95 % CI {s['bpb_ci95'][0]:.4f}..{s['bpb_ci95'][1]:.4f})"
    out = [f"# Benchmark: mq_mul8 = `{r['variant']}`",
           f"RTL BPB {f(r)}, PPL {r['ppl']:.4f} per byte, {r['bytes']:,} bytes in {r['crops']} crops",
           f"cycles START->done {r['done_clk']}, TB errors {r['tb_errors']}"]
    if 'wall_s' in r:
        out.append(f"wall {r['wall_s'] / 60:.1f} min on {r['jobs']} workers")
    for k in HEADS:
        if f'head{k}' in r:
            out.append(f"first {k} crops{' (the 1.3749 golden set)' if k == 256 else ''}: "
                       f"RTL BPB {f(r[f'head{k}'])}")
    if 'golden' in r:
        g = r['golden']
        out.append(f"Python golden (exact multiplier) on the same bytes: BPB {g['bpb']:.4f}; RTL - golden "
                   f"{g['delta_bpb']:+.5f} +- {g['delta_se']:.5f}; tokens with any logit mismatch "
                   f"{g['tokens_with_logit_mismatch']:,} ({'bit-exact' if g['bit_exact'] else 'NOT bit-exact'})")
    if 'emulator' in r:
        e = r['emulator']
        out.append(f"Python emulator (golden + this mq_mul8's table) on the same bytes: BPB {e['bpb']:.4f}; "
                   f"tokens with any logit mismatch vs RTL {e['tokens_with_logit_mismatch']:,} "
                   f"({'bit-exact' if e['bit_exact'] else 'NOT bit-exact'})")
    if 'vs_baseline' in r:
        b = r['vs_baseline']
        out.append(f"vs baseline {b['baseline']}: dBPB {b['delta_bpb']:+.5f} +- {b['delta_se']:.5f} "
                   f"(paired, 95 % CI {b['delta_ci95'][0]:+.5f}..{b['delta_ci95'][1]:+.5f})")
    return '\n\n'.join(out) + '\n'


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('bench', type=Path)
    ap.add_argument('run', type=Path)
    ap.add_argument('--baseline', type=Path)
    ap.add_argument('--variant')
    a = ap.parse_args()
    print(markdown(score(a.bench, a.run, a.baseline, a.variant)), end='')


if __name__ == '__main__':
    main()
