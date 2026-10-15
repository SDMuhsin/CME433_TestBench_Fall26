#!/usr/bin/env python3
"""Prepare an OpenSTA SDF for the CVC timing GLS (models/gen_cells.py, models/sram_sdf.v).

1. COND for the paired IOPATHs of non-unate cell arcs.

OpenSTA writes a pin pair with both a positive- and a negative-unate arc (xor2/xnor2 A,B->Y,
mux2 S->Y) as two unconditioned `(IOPATH A Y ...)` lines.  A simulator can only map both onto one
specify path, so the second silently overwrites the first.  models/gen_cells.py models such a pair as
two conditional paths; this script wraps each IOPATH in the matching `(COND <side-input state>`.
Which IOPATH is which comes from arcs.<corner>.rpt (sdf/write_sdf.tcl: report_dcalc arc order of one
instance per cell type, the order write_sdf uses), the conditions from the Liberty function.

2. Escaped instance names (only the 10 SRAM macros, `\\u_core.u_mem.GEN_SRAM[i].u_sram.u_sram `)
   become names.legal_name() identifiers: CVC's SDF reader rejects an escaped instance followed by a
   bit-selected pin ("u_core\\.u_mem...u_sram.WEN[1] illegal Verilog name") and then drops the rest
   of the file.  sdf/legal_netlist.py applies the same renaming to the netlist.

usage: fix_sdf.py <in.sdf> <arcs.rpt> <liberty> <out.sdf>     prints a summary line
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import liberty  # noqa: E402
from libfunc import unate_conds  # noqa: E402
from names import legal_name  # noqa: E402


def _unescape_path(tok):
    """SDF path with backslash escapes -> (instance, pin or None); '.' unescaped = divider"""
    parts, cur, i = [], "", 0
    while i < len(tok):
        if tok[i] == "\\":
            cur += tok[i + 1]
            i += 2
        elif tok[i] == ".":
            parts.append(cur)
            cur = ""
            i += 1
        else:
            cur += tok[i]
            i += 1
    parts.append(cur)
    if len(parts) == 1:
        return parts[0], None
    return ".".join(parts[:-1]), parts[-1]


def rename_escaped(line):
    def sub(m):
        inst, pin = _unescape_path(m.group(0))
        return legal_name(inst) + ("." + pin if pin is not None else "")
    return re.sub(r"[^\s()]*\\[^\s()]*", sub, line)


def main():
    sdf_in, arcs_rpt, lib_path, sdf_out = sys.argv[1:5]
    lib = {c.name(): c for c in liberty.parse(lib_path).sub("cell")}
    order = {}                                    # (cell, from, to) -> [sense, sense]
    for line in open(arcs_rpt):
        f = line.split()
        if len(f) > 4:
            order[(f[0], f[1], f[2])] = f[3:]
    conds = {}
    for (cell, a, y), senses in order.items():
        c = lib[cell]
        pins = {p.name(): p for p in c.sub("pin")}
        ins = [n for n, p in pins.items() if p.attrs.get("direction") == "input"]
        cp, cn = unate_conds(pins[y].attrs["function"], ins, a)
        conds[(cell, a, y)] = [{"positive_unate": cp, "negative_unate": cn}[s] for s in senses]
    out, celltype, seen, nfix, nren = [], None, {}, 0, 0
    iop = re.compile(r"^(\s*)\(IOPATH (\S+) (\S+) (.*)$")
    for line in open(sdf_in):
        m = re.search(r'\(CELLTYPE "([^"]+)"\)', line)
        if m:
            celltype, seen = m.group(1), {}
        m = iop.match(line)
        if m and (celltype, m.group(2), m.group(3)) in conds:
            key = (celltype, m.group(2), m.group(3))
            k = seen.get(key, 0)
            seen[key] = k + 1
            if k >= len(conds[key]):
                raise SystemExit("%s: more IOPATH %s %s than arcs" % (celltype, key[1], key[2]))
            line = "%s(COND %s\n%s (IOPATH %s %s %s)\n" % (m.group(1), conds[key][k], m.group(1),
                                                          m.group(2), m.group(3), m.group(4).rstrip())
            nfix += 1
        if "\\" in line:
            line = rename_escaped(line)
            nren += 1
        out.append(line)
    with open(sdf_out, "w") as f:
        f.writelines(out)
    print("fix_sdf: %d IOPATHs of %d non-unate cell/pin pairs got a COND, %d lines with escaped "
          "instance names renamed -> %s" % (nfix, len(conds), nren, sdf_out))


if __name__ == "__main__":
    main()
