#!/usr/bin/env python3
"""Toggle rates from an instance-scoped SAIF (as written by vcd2saif): maps each instance's output pin (Y/Q) toggle count
to the net it drives in the netlist, then reports (a) named buses requested on the command line, (b) top named buses,
(c) mean output toggles/cycle per hierarchy (needs the hier_attrib CSV). SDF vs zero-delay SAIF = glitch factor.
Usage: saif_toggles.py <netlist.v> <attrib.csv> <cycles> <saif> [<saif_zd>] -- bus1 bus2 ..."""
import re, sys, collections
args = sys.argv[1:]; sep = args.index('--'); nl, attr, cycles = args[0], args[1], float(args[2]); saifs = args[3:sep]; want = args[sep + 1:]
import csv
hier = {r['inst']: r['hier'] for r in csv.DictReader(open(attr))}
OUT = {'Q', 'Y', 'ZERO', 'ONE'}
cell_re = re.compile(r'^\s*(gf180mcu_\w+)\s+(\\?\S+)\s*\((.*?)\);', re.S | re.M); pin_re = re.compile(r'\.(\w+)\(\s*([^()]*?)\s*\)')
def clean(n): return n.strip().lstrip('\\').replace(' ', '')
outnet = {}
for ref, inst, body in cell_re.findall(open(nl).read()):
    for p, n in pin_re.findall(body):
        if p in OUT: outnet[clean(inst)] = clean(n)
def read(saif):
    tc = {}
    pin_tc = re.compile(r'\((\w+)\s*\(T0\s+\d+\)\s*\(T1\s+(\d+)\)\s*\(TX\s+\d+\)\s*\(TC\s+(\d+)\)')
    for line in open(saif):   # vcd2saif writes one (INSTANCE <cell> (NET (pin ...) ...)) per line
        m = re.match(r'\s*\(INSTANCE\s+(\S+)\s+\(NET', line)
        if not m: continue
        inst = m.group(1).replace('\\', '')
        for p, t1, c in pin_tc.findall(line):
            if p in OUT: tc[inst] = (int(c), int(t1))
    return tc
dur = float(re.search(r'\(DURATION\s+([\d.eE+-]+)\)', open(saifs[0]).read()).group(1))
res = [read(s) for s in saifs]
bus = collections.defaultdict(lambda: [0, 0, 0, 0.0]); byh = collections.defaultdict(lambda: [0, 0, 0])
for inst, (tc, t1) in res[0].items():
    n = outnet.get(inst, inst); base = re.sub(r'\[\d+\]$', '', n); b = bus[base]
    tc2 = res[1].get(inst, (tc, 0))[0] if len(res) > 1 else tc
    b[0] += 1; b[1] += tc; b[2] += tc2; b[3] += t1 / dur
    h = byh[hier.get(inst, '?')]; h[0] += 1; h[1] += tc; h[2] += tc2
print(f'# {saifs}: {cycles:.0f} cycles')
print(f'{"bus":46s} {"bits":>4s} {"tog/bit/cyc":>11s} {"zd":>7s} {"T1duty":>7s}')
for w in want:
    for k, (bits, tc, tc2, t1) in bus.items():
        if k == w or k.endswith('.' + w): print(f'{k[:46]:46s} {bits:4d} {tc/bits/cycles:11.3f} {tc2/bits/cycles:7.3f} {t1/bits:7.3f}')
print('# top named buses (>=4 bits) by toggles/bit/cycle:')
for k, (bits, tc, tc2, t1) in sorted(bus.items(), key=lambda x: -x[1][1] / x[1][0])[:22]:
    if bits >= 4 and not re.match(r'_\d+_$', k): print(f'{k[:46]:46s} {bits:4d} {tc/bits/cycles:11.3f} {tc2/bits/cycles:7.3f} {t1/bits:7.3f}')
print(f'# per hierarchy: cells, mean output toggles/cycle (sdf), (zero-delay), glitch ratio')
for h, (n, tc, tc2) in sorted(byh.items(), key=lambda x: -x[1][1])[:16]:
    print(f'{h[:46]:46s} {n:5d} {tc/n/cycles:8.3f} {tc2/n/cycles:8.3f} {tc/max(tc2,1):6.2f}')
