#!/usr/bin/env python3
"""SDF annotation coverage of a CVC compile (+sdfverbose +sdf_log_file <log>).

Every SDF statement (IOPATH, INTERCONNECT, SETUP/HOLD/WIDTH/PERIOD) must have produced an
annotation message in the CVC SDF log ("... delay set to", "MIPD set to", "limit set to",
"matched to"), and no SDF error may be reported.  Also checks that every timing check of every
instantiated model got a value from the SDF (checks never annotated keep their 0 default and could
never fire), except the documented placeholder $recrem checks of dfsrtp_2 (no Liberty arcs).

usage: sdf_coverage.py <fixed.sdf> <cvc sdf log> <netlist> <cells.v> <sram_sdf.v> [report]
Exit 0 only if coverage is 100 % and no SDF error was reported.
"""
import collections
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
from netlist import parse_netlist  # noqa: E402


def sdf_statements(path):
    """-> {line: kind, ...}, {line: instance}"""
    kinds, inst_of, inst = {}, {}, None
    for n, line in enumerate(open(path), 1):
        m = re.search(r"\(INSTANCE ?([^)]*)\)", line)
        if m:
            inst = m.group(1).strip()
        m = re.match(r"\s*\((IOPATH|INTERCONNECT|SETUP|HOLD|WIDTH|PERIOD|SETUPHOLD|RECOVERY|REMOVAL|RECREM)\b", line)
        if m:
            kinds[n] = m.group(1)
            inst_of[n] = inst
    return kinds, inst_of


def model_checks(path):
    """module -> list of (line, text) of timing checks in the specify block"""
    out, mod = collections.defaultdict(list), None
    for n, line in enumerate(open(path), 1):
        m = re.match(r"\s*module\s+(\w+)", line)
        if m:
            mod = m.group(1)
        if re.match(r"\s*\$(setuphold|setup|hold|width|period|recrem|recovery|removal)\b", line):
            out[mod].append((n, line.strip()))
    return out


def main():
    sdf, log, netlist, cells_v, sram_v = sys.argv[1:6]
    rpt = sys.argv[6] if len(sys.argv) > 6 else None
    kinds, inst_of = sdf_statements(sdf)
    sdf_base = sdf.split("/")[-1]
    done, errors, warns = set(), [], collections.Counter()
    tchk_hit = collections.defaultdict(set)       # instance -> {(file, line)} of annotated checks
    pat = re.compile(re.escape(sdf_base) + r"\((\d+)\)")
    for line in open(log):
        m = pat.search(line)
        if not m:
            continue
        n = int(m.group(1))
        if "ERROR**" in line:
            errors.append(line.strip())
        elif "WARN**" in line:
            warns[re.search(r"\[(\d+)\]", line).group(1)] += 1
        if re.search(r"delay set to|MIPD set to|limit set to|matched to", line) and "ERROR" not in line:
            done.add(n)
            t = re.search(r" in \S+\.(\S+?)\((\S+)\) at \*\*(\S+)\((\d+)\)", line)
            if "TIMINGCHECK" in line and t:
                tchk_hit[t.group(1)].add((t.group(3).split("/")[-1], int(t.group(4))))
        if "[667]" in line:                        # negative limit -> 0 still annotates the check
            done.add(n)
            t = re.search(r"at \*\*(\S+)\((\d+)\)", line)
    by = collections.Counter(kinds.values())
    hit = collections.Counter(kinds[n] for n in done if n in kinds)
    missing = sorted(n for n in kinds if n not in done)
    # instances: every netlist instance of a cell with timing arcs must appear in the SDF
    inst_cell = parse_netlist(netlist)[2]
    checks = {**model_checks(cells_v), **model_checks(sram_v)}
    timed = {c for c in set(inst_cell.values()) if c in checks or re.search(
        r"__(buff|clkbuff|dlybuff|inv|nand|nor|and|or|xnor|xor|mux|maj|aoi|ao|oai|dfx|dfs|dlx)", c)}
    sdf_insts = set(i for i in inst_of.values() if i)
    timed_insts = [i for i, c in inst_cell.items() if c in timed]
    inst_missing = [i for i in timed_insts if i not in sdf_insts]
    # timing checks of the models: every check line of every instance must be annotated
    exp_checks, got_checks, unann = 0, 0, collections.Counter()
    for i, c in inst_cell.items():
        for n, text in checks.get(c, []):
            if "$recrem" in text:
                continue                          # placeholder limits, no SDF data (documented)
            exp_checks += 1
            fname = (cells_v if c.startswith("gf180mcu_as") else sram_v).split("/")[-1]
            if (fname, n) in tchk_hit.get(i, ()):
                got_checks += 1
            else:
                unann[c] += 1
    recrem = sum(1 for i, c in inst_cell.items() for n, t in checks.get(c, []) if "$recrem" in t)
    lines = ["SDF annotation coverage: %s" % sdf, ""]
    lines.append("%-14s %8s %10s %8s" % ("statement", "in SDF", "annotated", "%"))
    for k in sorted(by):
        lines.append("%-14s %8d %10d %8.2f" % (k, by[k], hit[k], 100.0 * hit[k] / by[k]))
    tot, tothit = sum(by.values()), sum(hit.values())
    lines.append("%-14s %8d %10d %8.2f" % ("TOTAL", tot, tothit, 100.0 * tothit / tot))
    lines.append("")
    lines.append("instances with timing arcs: %d, in the SDF: %d (%.2f %%)" % (
        len(timed_insts), len(timed_insts) - len(inst_missing),
        100.0 * (len(timed_insts) - len(inst_missing)) / max(1, len(timed_insts))))
    lines.append("model timing checks (setuphold halves/setup/hold/width/period): %d, annotated from the "
                 "SDF: %d (%.2f %%)" % (exp_checks, got_checks, 100.0 * got_checks / max(1, exp_checks)))
    lines.append("placeholder $recrem checks (dfsrtp_2 RN/SN, no Liberty arcs): %d" % recrem)
    lines.append("negative hold limits clamped to 0 by CVC ([667]): %d" % warns.get("667", 0))
    lines.append("SDF errors: %d; warnings by id: %s" % (len(errors), dict(warns)))
    for n in missing[:20]:
        lines.append("  NOT ANNOTATED line %d: %s" % (n, kinds[n]))
    for c, k in unann.most_common(10):
        lines.append("  unannotated checks in %s: %d" % (c, k))
    for i in inst_missing[:10]:
        lines.append("  instance not in SDF: %s (%s)" % (i, inst_cell[i]))
    for e in errors[:10]:
        lines.append("  " + e)
    ok = not missing and not errors and not inst_missing and got_checks == exp_checks
    lines.append("SDF_COVERAGE %s" % ("OK 100 %" if ok else "INCOMPLETE"))
    text = "\n".join(lines)
    print(text)
    if rpt:
        open(rpt, "w").write(text + "\n")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
