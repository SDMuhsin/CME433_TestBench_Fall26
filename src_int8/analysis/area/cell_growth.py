#!/usr/bin/env python3
"""Per-step std-cell count by class from each LibreLane step's *.nl.v (INT8 mq_final vs FP16 mb_final).
Classes: logic, buf/inv (repair/hold/CTS: attribute by step delta), ff, tap, diode, tie, sram (fill excluded from total)."""
import re, sys, glob, os
CELL = re.compile(r'^\s*(gf180mcu_\w+|\w*sram\w*)\s+(\\?\S+)\s*\(', re.M)
def classify(c):   # gf180mcu_as_sc_mcu7t3v3 names
    c = c.split('__')[-1]
    if 'sram' in c: return 'sram'
    if c.startswith(('dfxtp', 'dfsrtp', 'dfxtn', 'dlx')): return 'ff'
    if c.startswith('fill'): return 'fill'
    if c.startswith(('tap', 'endcap')): return 'tap'
    if c.startswith('diode'): return 'diode'
    if c.startswith('tie'): return 'tie'
    if c.startswith(('buff', 'clkbuff', 'dlybuff', 'inv', 'clkinv')): return 'buf/inv'
    return 'logic'
def count(path):
    txt = open(path).read()
    d = {}
    for c, _ in CELL.findall(txt):
        k = classify(c); d[k] = d.get(k, 0) + 1
    d['total'] = sum(v for k, v in d.items() if k != 'fill'); return d
def run(rundir, top):
    rows = []
    for step in sorted(glob.glob(os.path.join(rundir, '[0-9][0-9]-*'))):
        f = os.path.join(step, f'{top}.nl.v')
        if os.path.exists(f): rows.append((os.path.basename(step), count(f)))
    f = os.path.join(rundir, 'final', 'nl', f'{top}.nl.v')
    if os.path.exists(f): rows.append(('final', count(f)))
    cols = ['total', 'logic', 'buf/inv', 'ff', 'tap', 'diode', 'tie', 'sram']
    print(rundir); print(f"{'step':40s}" + ''.join(f'{c:>9s}' for c in cols))
    prev = None
    for name, d in rows:
        if prev and all(d.get(c, 0) == prev.get(c, 0) for c in cols): continue
        print(f"{name[:40]:40s}" + ''.join(f"{d.get(c,0):9d}" for c in cols)); prev = d
for rd, top in [('src_int8/flow/runs/mq_final', 'mq_chip'), ('src/flow/runs/mb_final', 'mb_chip')]:
    run(rd, top); print()
