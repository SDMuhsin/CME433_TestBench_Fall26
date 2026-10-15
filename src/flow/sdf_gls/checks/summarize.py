#!/usr/bin/env python3
"""Summary table of SDF GLS runs -> stdout (and <build>/summary.rpt).

usage: summarize.py <src/flow/build/sdf_gls> [run dir name ...]   (default: every dir with gls.log)
Per run: tokens bit-exact, timing-check violations, SRAM-model errors, output-timing violations,
worst output settle, cycles/token, SDF coverage, sim wall time.
"""
import os
import re
import sys


def one(d):
    log = os.path.join(d, "gls.log")
    txt = open(log, errors="replace").read()
    toks = re.findall(r"^TOKEN \d+ byte \w+: (\d+)/(\d+) logits", txt, re.M)
    exact = sum(1 for a, b in toks if a == b)
    viol = len(re.findall(r"\[566\] timing violation", txt))
    sram = txt.count("---- ERROR:")
    io = re.search(r"^IO: worst output settle after clk ([\d.]+) ns .*?, (\d+) output-timing", txt, re.M)
    cyc = re.search(r"^CYCLES/TOKEN (\d+)", txt, re.M)
    verdict = "PASS" if re.search(r"^PASS", txt, re.M) else "FAIL"
    cov = "-"
    cr = os.path.join(d, "coverage.rpt")
    if os.path.exists(cr):
        c = open(cr).read()
        m = re.search(r"^TOTAL\s+(\d+)\s+(\d+)\s+([\d.]+)", c, re.M)
        cov = "%s %%" % m.group(3) if m else ("zero-delay" if "NOSDF" in c else "?")
    wall = "-"
    tr = os.path.join(d, "timing.rpt")
    if os.path.exists(tr):
        m = re.search(r"sim wall (\d+)s", open(tr).read())
        wall = "%.1f h" % (int(m.group(1)) / 3600.0) if m else "-"
    return (os.path.basename(d), verdict, "%d/%d" % (exact, len(toks)), viol, sram,
            io.group(2) if io else "-", io.group(1) if io else "-", cyc.group(1) if cyc else "-", cov, wall)


def main():
    top = sys.argv[1]
    names = sys.argv[2:] or sorted(n for n in os.listdir(top) if os.path.exists(os.path.join(top, n, "gls.log")))
    hdr = ("run", "TB", "tokens exact", "tchk viol", "SRAM err", "IO viol", "worst out settle ns",
           "clk/token", "SDF coverage", "sim wall")
    rows = [hdr] + [one(os.path.join(top, n)) for n in names]
    w = [max(len(str(r[i])) for r in rows) for i in range(len(hdr))]
    text = "\n".join("  ".join(str(c).ljust(w[i]) for i, c in enumerate(r)) for r in rows) + "\n"
    print(text, end="")
    open(os.path.join(top, "summary.rpt"), "w").write(text)


if __name__ == "__main__":
    main()
