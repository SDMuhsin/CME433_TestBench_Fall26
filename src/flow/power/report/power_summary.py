#!/usr/bin/env python3
"""Summary of the activity-based power runs (run_power.sh) -> <power dir>/summary.rpt.

For every corner: OpenSTA report_power groups (internal / switching / leakage / total) with the
SDF-GLS SAIF, vectorless, and SAIF + flop power proxy; activity annotation; an independent SRAM
check (TB access counts x Liberty CLK internal_power energies); energy per token.

usage: power_summary.py <power dir> <sdf_gls build dir> <corner> [<corner> ...]
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import liberty  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".."))
T_TOKEN_MS = 32.04          # START -> done, 801,056 clk at 25 MHz (RTL / zero-delay GLS)
GROUPS = ("Sequential", "Combinational", "Clock", "Macro", "Pad", "Total")


def read_power(path):
    rows = {}
    if not os.path.exists(path):
        return None
    for line in open(path):
        f = line.split()
        if f and f[0] in GROUPS and len(f) >= 5:
            rows[f[0]] = [float(x) for x in f[1:5]]
    return rows


def read_activity(path):
    d = {}
    if os.path.exists(path):
        for line in open(path):
            f = line.split()
            if len(f) == 2 and f[1].isdigit():
                d[f[0]] = int(f[1])
    return d


def sram_energies(pvt):
    lib = liberty.parse(os.path.join(ROOT, "gf180mcu_ocd_ip_sram__sram256x8m8wm1",
                                     "gf180mcu_ocd_ip_sram__sram256x8m8wm1__%s.lib" % pvt))
    cell = lib.sub("cell")[0]
    clk = [p for p in cell.sub("pin") if p.name() == "CLK"][0]
    e = {}
    for ip in clk.sub("internal_power"):
        w = ip.attrs.get("when", "")
        tot = 0.0
        for kind in ("rise_power", "fall_power"):
            for g in ip.sub(kind):
                vals = [v for n, v in g.cattrs if n == "values"][0]
                tot += float(vals[0].split(",")[0])
        key = "write" if "GWEN" in w and "!GWEN" in w else "read" if "GWEN" in w else "disabled"
        e[key] = tot                               # pJ per clock cycle (rise + fall)
    leak = float(cell.attrs.get("cell_leakage_power", 0)) * 1e-3   # mW -> W
    return e, leak


def gls_counts(log):
    rd, wr, n, win = {}, {}, None, None
    for line in open(log):
        m = re.match(r"SRAM (\d+): (\d+) reads, (\d+) writes", line)
        if m:
            rd[int(m.group(1))], wr[int(m.group(1))] = int(m.group(2)), int(m.group(3))
        m = re.match(r"VCD: window (\d+) clk", line)
        if m:
            n = int(m.group(1))
        m = re.match(r"VCD: window ([\d.]+) \.\. ([\d.]+) ns", line)
        if m:
            win = (float(m.group(1)), float(m.group(2)))
    return rd, wr, n, win


def fmt(rows, g):
    i, s, l, t = rows[g]
    return "%-13s %9.3f %9.3f %9.4f %9.3f" % (g, i * 1e3, s * 1e3, l * 1e3, t * 1e3)


def main():
    pdir, gdir = sys.argv[1:3]
    corners = sys.argv[3:]
    out = ["mb_chip activity-based power (OpenSTA report_power, SPEF of the corner, signoff SDC)",
           "activity: SDF GLS of the same corner, token 1 ('n') of the story \"On\", window = START .. end of",
           "logit readback; energy/token = total power x %.2f ms (START->done)" % T_TOKEN_MS, ""]
    summary = []
    for c in corners:
        pvt = c.split("_", 1)[1]
        out.append("=" * 78)
        out.append("corner %s" % c)
        rd, wr, n, win = gls_counts(os.path.join(gdir, "%s_power" % c, "gls.log"))
        act = read_activity(os.path.join(pdir, "activity.%s.saif.rpt" % c))
        if win:
            out.append("activity window %.3f .. %.3f ns = %.4f ms, %s clk; SAIF annotated pins %s, unannotated %s"
                       % (win[0], win[1], (win[1] - win[0]) * 1e-6, n, act.get("saif"), act.get("unannotated")))
        for tag, title in (("saif", "SAIF (SDF GLS activity, glitches included)"),
                           ("saif_proxy", "SAIF + flop power proxy (fd_sc 7t5v0 dffq/dffrsnq, estimate)"),
                           ("zero_delay", "SAIF from the zero-delay GLS (no glitches)"),
                           ("vectorless", "vectorless (OpenSTA default activity, as the LibreLane signoff)")):
            rows = read_power(os.path.join(pdir, "power.%s.%s.rpt" % (c, tag)))
            if not rows:
                continue
            out.append("")
            out.append("%s  [mW]" % title)
            out.append("%-13s %9s %9s %9s %9s" % ("group", "internal", "switching", "leakage", "total"))
            for g in GROUPS:
                if g in rows:
                    out.append(fmt(rows, g))
            tot = rows["Total"][3]
            out.append("energy/token %.1f uJ (%.2f ms x %.3f mW)" % (tot * T_TOKEN_MS * 1e-3 * 1e6, T_TOKEN_MS, tot * 1e3))
            summary.append((c, tag, tot, rows))
        if rd and n:
            e, leak = sram_energies(pvt)
            tclk = 40e-9
            p = 0.0
            for i in rd:
                p += (rd[i] * e["read"] + wr[i] * e["write"] + (n - rd[i] - wr[i]) * e["disabled"]) * 1e-12
            p = p / (n * tclk) + 10 * leak
            sta = read_power(os.path.join(pdir, "power.%s.saif.rpt" % c))
            out.append("")
            out.append("SRAM check: Liberty CLK energy per cycle read %.1f / write %.1f / disabled %.2g pJ (rise+fall);"
                       % (e["read"], e["write"], e["disabled"]))
            out.append("  TB counts: reads %s, writes %s of %d clk" % (sum(rd.values()), sum(wr.values()), n))
            out.append("  per macro: " + ", ".join("%d:%d/%d" % (i, rd[i], wr[i]) for i in sorted(rd)))
            out.append("  counted SRAM power %.3f mW vs OpenSTA Macro %.3f mW (state probabilities)"
                       % (p * 1e3, sta["Macro"][3] * 1e3 if sta else float("nan")))
        out.append("")
    out.append("=" * 78)
    out.append("%-18s %-11s %10s %14s" % ("corner", "activity", "total mW", "uJ/token"))
    for c, tag, tot, rows in summary:
        out.append("%-18s %-11s %10.3f %14.1f" % (c, tag, tot * 1e3, tot * T_TOKEN_MS * 1e3))
    text = "\n".join(out) + "\n"
    open(os.path.join(pdir, "summary.rpt"), "w").write(text)
    print(text)


if __name__ == "__main__":
    main()
