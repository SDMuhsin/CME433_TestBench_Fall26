#!/usr/bin/env python3
"""Observed setup/hold margins from a timing GLS ("margin probe").

A passing SDF GLS only says that no check fired.  To measure how close the simulated transitions
come to the limits, a probe run adds P ns to every SETUP (or HOLD) limit of the SDF, so that every
data transition within P ns of its limit is reported by the simulator with the measured
data-to-clock separation ("diff"); the cell models are compiled with +define+MB_TCHK_PROBE so the
reports do not corrupt the state.  The observed margin of a reported check is
    hold:  (data - clk) - limit        setup: (clk - data) - limit
with limit = the SDF value (the inflated value minus P).  Checks that are never reported have an
observed margin >= P.

  margin_probe.py make  <in.sdf> <out.sdf> setup|hold <P ns>
  margin_probe.py reduce setup|hold <P ns> <report> [N]   (stdin: simulator output; non-violation
                                                          lines are passed to stdout)
Reports before AFTER_PS (default 1 us, i.e. before/at reset release: X -> 0/1 resolution of the
power-up state) are counted separately and not used.
"""
import collections
import os
import re
import sys

AFTER_PS = int(os.environ.get("AFTER_PS", "1000000"))

VIOL = re.compile(r"\[566\] timing violation in (\S+) \(diff\. (-?\d+) ps\)")
DETAIL = re.compile(r"^\s*\$?(setup|hold)(?:\(of setuphold\))?\(\((\w+) ([^:)&]+)[^:]*\):(\d+) ps, "
                    r"\((\w+) ([^:)&]+)[^:]*\):(\d+) ps, (-?\d+) ps\);")


def make(src, dst, kind, p):
    key = "(%s " % kind.upper()
    num = re.compile(r"-?\d+\.\d+")
    n = 0
    with open(src) as f, open(dst, "w") as g:
        for line in f:
            if line.lstrip().startswith(key):
                head, tail = line.rsplit("(", 1)       # last parenthesis = the value triple
                tail = num.sub(lambda v: "%.3f" % (float(v.group(0)) + p), tail)
                line = head + "(" + tail
                n += 1
            g.write(line)
    print("margin_probe: %s limits +%.3f ns on %d checks -> %s" % (kind.upper(), p, n, dst))


def reduce(kind, p, report, top):
    pps = int(round(p * 1000))
    worst = {}                                    # (inst, check) -> (margin ps, time ps)
    count = collections.Counter()
    pend = None
    other = early = 0
    for line in sys.stdin:
        m = VIOL.search(line)
        if m:
            pend = (m.group(1), int(m.group(2)))
            continue
        if pend:
            d = DETAIL.match(line)
            inst, diff = pend
            pend = None
            if d and d.group(1) == kind:
                # the data terminal is the one that is not CLK
                if d.group(3).strip().startswith("CLK"):
                    edge, pin, t = d.group(5), d.group(6).strip(), int(d.group(7))
                else:
                    edge, pin, t = d.group(2), d.group(3).strip(), int(d.group(4))
                limit = int(d.group(8)) - pps
                margin = diff - limit
                if max(int(d.group(4)), int(d.group(7))) < AFTER_PS:
                    early += 1
                    continue
                k = (inst.split(".")[-1], "%s %s" % (edge, pin))
                count[k] += 1
                if k not in worst or margin < worst[k][0]:
                    worst[k] = (margin, t, limit)
                continue
            other += 1
            sys.stdout.write("UNPARSED-VIOLATION %s diff %d: %s" % (inst, diff, line))
            continue
        sys.stdout.write(line)
    rows = sorted(worst.items(), key=lambda kv: kv[1][0])
    with open(report, "w") as f:
        f.write("%s margin probe: limits +%.3f ns; %d checks reported (%d reports), %d other violations, "
                "%d reports before %d ps ignored\n" % (kind, p, len(worst), sum(count.values()), other, early, AFTER_PS))
        f.write("checks never reported have an observed %s margin >= %.3f ns\n" % (kind, p))
        f.write("%-40s %-14s %10s %10s %8s %14s\n" % ("instance", "data", "margin_ns", "limit_ns", "reports", "first_worst_ps"))
        for (inst, chk), (mg, t, lim) in rows[:top]:
            f.write("%-40s %-14s %10.3f %10.3f %8d %14d\n" % (inst, chk, mg / 1000.0, lim / 1000.0, count[(inst, chk)], t))
        sram = [r for r in rows if "GEN_SRAM" in r[0][0]]
        if sram:
            (inst, chk), (mg, t, lim) = sram[0]
            f.write("WORST_SRAM_%s_MARGIN %.3f ns at %s %s (limit %.3f ns, %d SRAM checks reported)\n"
                    % (kind.upper(), mg / 1000.0, inst, chk, lim / 1000.0, len(sram)))
        else:
            f.write("WORST_SRAM_%s_MARGIN >= %.3f ns (no SRAM check reported)\n" % (kind.upper(), p))
        if rows:
            f.write("WORST_OBSERVED_%s_MARGIN %.3f ns at %s %s\n" % (kind.upper(), rows[0][1][0] / 1000.0, rows[0][0][0], rows[0][0][1]))
        else:
            f.write("WORST_OBSERVED_%s_MARGIN >= %.3f ns (nothing reported)\n" % (kind.upper(), p))


def main():
    a = sys.argv[1:]
    if a and a[0] == "make":
        make(a[1], a[2], a[3], float(a[4]))
    elif a and a[0] == "reduce":
        reduce(a[1], float(a[2]), a[3], int(a[4]) if len(a) > 4 else 40)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
