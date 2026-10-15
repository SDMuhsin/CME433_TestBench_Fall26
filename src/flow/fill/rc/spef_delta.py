#!/usr/bin/env python3
"""Per-net total capacitance (SPEF *D_NET) of two runs, per RC corner: how much the fill adds.

    python3 -I spef_delta.py <TAG> <TAG>_fillrc        (tags under src/flow/runs, or run dirs)
"""
import glob
import os
import sys

FLOW = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def caps(run, corner):
    f = glob.glob(os.path.join(run, "*-openroad-rcx", corner, "*.spef"))
    if not f:
        sys.exit(f"no {corner} SPEF in {run}")
    out, scale = {}, 1.0
    names = {}
    for line in open(f[0]):
        if line.startswith("*C_UNIT"):
            v, u = line.split()[1:3]
            scale = float(v) * {"PF": 1.0, "FF": 1e-3}[u.upper()]
        elif line.startswith("*D_NET"):
            _, n, c = line.split()[:3]
            out[names.get(n, n)] = float(c) * scale
        elif line.startswith("*") and line[1:2].isdigit() and " " in line and not out:
            k, v = line.split(None, 1)
            names[k] = v.strip()
    return out


def main():
    a, b = (p if os.path.isdir(p) else os.path.join(FLOW, "runs", p) for p in sys.argv[1:3])
    print(f"{'corner':6} {'nets':>6} {'sum_before_pF':>13} {'sum_after_pF':>12} {'total%':>7} "
          f"{'median%':>7} {'p99%':>6} {'max%':>6} {'max_abs_fF':>10}")
    for corner in ("nom", "min", "max"):
        ca, cb = caps(a, corner), caps(b, corner)
        common = [n for n in ca if n in cb and ca[n] > 0]
        rel = sorted((cb[n] - ca[n]) / ca[n] * 100 for n in common)
        dab = max(cb[n] - ca[n] for n in common) * 1e3
        sa, sb = sum(ca[n] for n in common), sum(cb[n] for n in common)
        print(f"{corner:6} {len(common):6d} {sa:13.2f} {sb:12.2f} {(sb - sa) / sa * 100:7.2f} "
              f"{rel[len(rel) // 2]:7.2f} {rel[int(len(rel) * 0.99)]:6.2f} {rel[-1]:6.2f} {dab:10.2f}")


if __name__ == "__main__":
    main()
