#!/usr/bin/env python3
"""Join an OpenSTA report_power -instances dump with the hier_attrib CSV; print power (mW) by hierarchy and by origin.
Usage: power_by_hier.py <power_inst.rpt> <attrib.csv> [topN]"""
import sys, csv, collections
rpt, attr = sys.argv[1:3]; topn = int(sys.argv[3]) if len(sys.argv) > 3 else 25
h = {r['inst']: (r['hier'], r['origin'], r['ref']) for r in csv.DictReader(open(attr))}
byh = collections.defaultdict(lambda: [0.0, 0.0, 0]); byho = collections.defaultdict(lambda: [0.0, 0.0, 0.0, 0]); byo = collections.defaultdict(lambda: [0.0, 0.0, 0]); byref = collections.defaultdict(lambda: [0.0, 0])
tot = [0.0, 0.0]
for line in open(rpt):
    f = line.split()
    if len(f) != 5: continue
    try: i, s, l, t = map(float, f[:4])
    except ValueError: continue
    inst = f[4]; hier, orig, ref = h.get(inst, ('(not in csv)', 'sram' if 'sram' in inst else '?', inst))
    byh[hier][0] += i; byh[hier][1] += s; byh[hier][2] += 1
    byo[orig][0] += i; byo[orig][1] += s; byo[orig][2] += 1
    k = 0 if orig == 'cts' else 1 if orig in ('synth', 'tie') else 2; byho[hier][k] += i + s; byho[hier][3] += ('dfxtp' in ref or 'dfsrtp' in ref)
    byref[ref.split('__')[-1]][0] += i + s; byref[ref.split('__')[-1]][1] += 1
    tot[0] += i; tot[1] += s
print(f'# {rpt}\n# total internal {tot[0]*1e3:.3f} mW switching {tot[1]*1e3:.3f} mW')
print(f'{"origin":10s} {"cells":>6s} {"int_mW":>8s} {"sw_mW":>8s} {"tot_mW":>8s}')
for o, (i, s, n) in sorted(byo.items(), key=lambda x: -(x[1][0] + x[1][1])): print(f'{o:10s} {n:6d} {i*1e3:8.3f} {s*1e3:8.3f} {(i+s)*1e3:8.3f}')
print(f'{"hier":40s} {"cells":>6s} {"int_mW":>8s} {"sw_mW":>8s} {"tot_mW":>8s}')
for hh, (i, s, n) in sorted(byh.items(), key=lambda x: -(x[1][0] + x[1][1]))[:topn]: print(f'{hh[:40]:40s} {n:6d} {i*1e3:8.3f} {s*1e3:8.3f} {(i+s)*1e3:8.3f}')
print(f'{"hier (split)":40s} {"flops":>5s} {"cts_mW":>7s} {"logic_mW":>8s} {"repair_mW":>9s}')
for hh, (c, l, r, nf) in sorted(byho.items(), key=lambda x: -(x[1][0] + x[1][1] + x[1][2]))[:14]: print(f'{hh[:40]:40s} {nf:5d} {c*1e3:7.3f} {l*1e3:8.3f} {r*1e3:9.3f}')
print(f'{"ref":14s} {"cells":>6s} {"tot_mW":>8s}')
for r, (p, n) in sorted(byref.items(), key=lambda x: -x[1][0])[:12]: print(f'{r:14s} {n:6d} {p*1e3:8.3f}')
