"""Exhaustive error analysis of a mq_mul8 variant (all 65,536 signed input pairs, RTL simulation).

python3 -m src_int8.approx.err.run <variant> [-D NAME=VALUE ...] [--ref <model>] [--hist <npy>]
  <variant>   exact | <name> (src_int8/bench/variants/<name>.v or <name>/) | path to .v / dir
  -D          macro definitions for a configurable variant (e.g. -D CSSM_M=4)
  --ref       reference model src_int8/approx/ref/<model>.py, function table(**defines):
              checks the RTL table against it bit for bit
  --hist      operand histogram (256 x 256, from src_int8.approx.act.hist): adds metrics
              weighted by the chip's real weight x activation distribution
Writes build/approx/err/<tag>.json and <tag>_table.npy; prints the metrics.
"""
import argparse
import importlib
import json
from pathlib import Path

import numpy as np

from ...bench.emu.table import mul8_table
from .metrics import EXACT, metrics

ROOT = Path(__file__).resolve().parents[3]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('variant')
    ap.add_argument('-D', dest='defines', action='append', default=[])
    ap.add_argument('--ref')
    ap.add_argument('--hist', type=Path)
    ap.add_argument('--out', type=Path, default=ROOT / 'build/approx/err')
    a = ap.parse_args()
    tag = Path(a.variant).stem + ''.join('_' + d.replace('=', '') for d in a.defines)
    a.out.mkdir(parents=True, exist_ok=True)
    t = mul8_table(a.variant, a.out / f'{tag}_sim', a.defines)
    np.save(a.out / f'{tag}_table.npy', t)
    res = dict(variant=a.variant, defines=a.defines, inputs=65536, uniform=metrics(t))
    if a.ref:
        kw = dict(d.split('=', 1) for d in a.defines)
        ref = importlib.import_module(f'src_int8.approx.ref.{a.ref}').table(**kw)
        res['rtl_vs_ref'] = dict(model=a.ref, mismatches=int((ref != t).sum()))
    if a.hist:
        res['chip_operands'] = metrics(t, np.load(a.hist))
    (a.out / f'{tag}.json').write_text(json.dumps(res, indent=1) + '\n')
    print(f'{tag}: differs from exact on {int((t != EXACT).sum())} / 65536 inputs')
    for k in ('uniform', 'chip_operands'):
        if k in res:
            m = res[k]
            print(f'  {k:13s} ER {m["ER"]:.4f}  MED {m["MED"]:.3f}  NMED {m["NMED"]:.3e}  MRED {m["MRED"]:.3e}  '
                  f'max {m["max_abs_error"]}  bias {m["bias"]:+.4f} (NM {m["NM"]:+.3e})  NoEB {m["NoEB"]:.2f}  '
                  f'PRED {m["PRED"]:.3e}  err@0 {m["error_at_zero_operand"]}')
    if 'rtl_vs_ref' in res:
        print(f'  RTL vs ref model {a.ref}: {res["rtl_vs_ref"]["mismatches"]} mismatches of 65536')


if __name__ == '__main__':
    main()
