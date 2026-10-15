#!/usr/bin/env python3
"""Which nets did the resizer buffer / DRT diode? For repair cells (fanout*/wire*/max_cap*/max_length*/ANTENNA_*) list the
hierarchical name of the buffered net (first hierarchical name reached backwards through buffer chains), count and power.
Usage: repair_nets.py <final.nl.v> <attrib.csv> <power_inst.rpt> [topN]"""
import re, sys, csv, collections
nl, attr, rpt = sys.argv[1:4]; topn = int(sys.argv[4]) if len(sys.argv) > 4 else 25
OUT = {'Q', 'Y', 'ZERO', 'ONE'}
cell_re = re.compile(r'^\s*(gf180mcu_\w+)\s+(\\?\S+)\s*\((.*?)\);', re.S | re.M); pin_re = re.compile(r'\.(\w+)\(\s*([^()]*?)\s*\)')
def clean(n): return n.strip().lstrip('\\').replace(' ', '')
drv = {}; cells = {}
for ref, inst, body in cell_re.findall(open(nl).read()):
    inst = clean(inst); o = []; i = []
    for p, n in pin_re.findall(body):
        n = clean(n)
        if n and not n.startswith("1'"): (o if p in OUT else i).append((p, n))
    cells[inst] = (ref, o, i)
    for _, n in o: drv[n] = inst
pw = {}
for line in open(rpt):
    f = line.split()
    if len(f) == 5:
        try: pw[f[4]] = float(f[0]) + float(f[1])
        except ValueError: pass
orig = {r['inst']: r['origin'] for r in csv.DictReader(open(attr))}
def src_name(inst):   # walk back through buffers to the original driver / first hierarchical net
    seen = set()
    while inst and inst not in seen and len(seen) < 40:
        seen.add(inst); ref, o, i = cells[inst]
        if not i: return inst
        n = i[0][1] if orig.get(inst, 'synth') != 'synth' else None
        if n is None: return (o[0][1] if o else inst)
        if '.' in n: return n
        inst = drv.get(n)
    return '?'
per_origin = collections.defaultdict(lambda: collections.defaultdict(lambda: [0, 0.0]))
for inst, (ref, o, i) in cells.items():
    og = orig.get(inst, 'synth')
    if og in ('fanout', 'wire', 'max_cap', 'diode', 'hold'):
        key = re.sub(r'\[\d+\]$', '', src_name(inst)); d = per_origin[og][key]; d[0] += 1; d[1] += pw.get(inst, 0.0)
for og, d in per_origin.items():
    print(f'### {og}: {sum(v[0] for v in d.values())} cells on {len(d)} distinct source nets/drivers; top by count:')
    for k, (c, p) in sorted(d.items(), key=lambda x: -x[1][0])[:topn]: print(f'  {c:5d} {p*1e6:8.1f} uW  {k[:70]}')
    print('  top by power:')
    for k, (c, p) in sorted(d.items(), key=lambda x: -x[1][1])[:8]: print(f'  {c:5d} {p*1e6:8.1f} uW  {k[:70]}')
