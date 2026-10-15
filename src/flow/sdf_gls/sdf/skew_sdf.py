#!/usr/bin/env python3
"""Negative-test SDF edit: add a delay to the INTERCONNECTs that end on given pins.

Delaying the clock pin of a capturing register (flop CLK or SRAM CLK) by more than its hold
slack must make the simulator's $setuphold / $hold checks fire; a GLS that still reports
0 violations would prove the checks are not active.
usage: skew_sdf.py <in.sdf> <out.sdf> <inst.pin>=<delta ns> [...]
"""
import re
import sys


def main():
    src, dst = sys.argv[1:3]
    edits = {}
    for a in sys.argv[3:]:
        pin, d = a.split("=")
        edits[pin] = float(d)
    hit = dict.fromkeys(edits, 0)
    num = re.compile(r"-?\d+\.\d+")
    with open(src) as f, open(dst, "w") as g:
        for line in f:
            m = re.match(r"(\s*\(INTERCONNECT \S+ )(\S+)( .*)$", line)
            if m and m.group(2) in edits:
                d = edits[m.group(2)]
                tail = num.sub(lambda v: "%.3f" % (float(v.group(0)) + d), m.group(3))
                line = m.group(1) + m.group(2) + tail + "\n"
                hit[m.group(2)] += 1
            g.write(line)
    for p, n in hit.items():
        if n == 0:
            raise SystemExit("skew_sdf: no INTERCONNECT ends on %s" % p)
        print("skew_sdf: +%.3f ns on %d INTERCONNECT(s) into %s" % (edits[p], n, p))


if __name__ == "__main__":
    main()
