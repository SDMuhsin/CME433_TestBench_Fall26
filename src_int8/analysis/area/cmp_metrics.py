#!/usr/bin/env python3
"""Compare LibreLane final/metrics.json of mq_final (INT8) vs mb_final (FP16); print metrics that differ."""
import json, sys, re
A = "src_int8/flow/runs/mq_final/final/metrics.json"
B = "src/flow/runs/mb_final/final/metrics.json"
a = json.load(open(A)); b = json.load(open(B))
pat = re.compile(sys.argv[1]) if len(sys.argv) > 1 else None
keys = sorted(set(a) | set(b))
print(f"{'metric':70s} {'INT8 mq':>14s} {'FP16 mb':>14s}")
for k in keys:
    if pat and not pat.search(k): continue
    va, vb = a.get(k), b.get(k)
    if va == vb: continue
    if isinstance(va, float): va = round(va, 3)
    if isinstance(vb, float): vb = round(vb, 3)
    print(f"{k[:70]:70s} {str(va)[:14]:>14s} {str(vb)[:14]:>14s}")
