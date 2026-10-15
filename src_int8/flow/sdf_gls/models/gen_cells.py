#!/usr/bin/env python3
"""Timing-annotatable Verilog models for gf180mcu_as_sc_mcu7t3v3 (SDF GLS).

The library's own Verilog (libs.ref/.../verilog/gf180mcu_as_sc_mcu7t3v3.v) is functional only: it
has no specify blocks, so an SDF has nothing to annotate and no timing check can fire.  This
script keeps every module body as it is (the function the zero-delay GLS already proved) and adds:
  * an output buffer (`buf (Y, Y_i)`) so module path delays apply to the port;
  * in sequential cells, a continuous-assign copy per input (`assign CLK_d = CLK`, body uses
    CLK_d ...):
    CVC applies an SDF INTERCONNECT (= MIPD, module input port delay) of a port to gates and
    continuous assigns, but NOT to procedural event controls/reads of that port.  Without the
    buffer, `always @(posedge CLK)` fires at the undelayed edge, before the delayed CLK the
    specify path is measured from, and the CLK->Q path delay is lost (Q changed with the clock;
    found as 27 ps hold "margins" on synchroniser flops, reproduced on a 2-cell test).  (A `buf`
    gate works for scalars, but a `buf` instance ARRAY on a vector port with MIPDs corrupted a bit
    in the SRAM model, so assigns are used everywhere);
  * one specify path per Liberty timing arc (combinational, rising_edge, falling_edge).
    Pin pairs with BOTH a positive_unate and a negative_unate arc (xor/xnor A,B; mux2 S) get two
    conditional paths `if (cond) (A => Y)`, the conditions derived from the Liberty function
    (side-input states where the arc is positive / negative).  sdf/fix_sdf.py adds the matching COND
    to OpenSTA's two unconditioned IOPATHs (it writes the arcs in Liberty order);
  * $setuphold per data edge for setup_*/hold_* arcs, $width for min_pulse_width_high/low;
  * $recrem for asynchronous clear/preset pins.  The Liberty has NO recovery/removal arcs (and no
    RN/SN->Q arcs) for dfsrtp_2, so neither STA nor the SDF covers them: the checks use the fixed
    placeholder limits REC_NS/REM_NS below (conservative vs the GF180 7t5v0 dffrsnq ss values);
  * a notifier on every check of a sequential cell that drives the state to X, through a wire
    (CVC crash otherwise, see cell_model) (not with
    +define+MQ_TCHK_PROBE: margin-probe runs report violations of inflated limits but must keep
    simulating correctly, see checks/margin_probe.py).
Check limits default to 0 and path delays to 0: the SDF must annotate them (checks/sdf_coverage.py).

usage: gen_cells.py <liberty> <functional .v> <out .v>
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
import liberty  # noqa: E402
from libfunc import unate_conds  # noqa: E402

REC_NS = 1.0     # placeholder recovery (async clear/preset release -> CLK)
REM_NS = 2.5     # placeholder removal  (CLK -> async clear/preset release)


def split_modules(text):
    mods = {}
    for m in re.finditer(r"module\s+(\w+)\s*\((.*?)\);(.*?)endmodule", text, re.S):
        mods[m.group(1)] = (m.group(2), m.group(3))
    return mods


def cell_model(cell, header, body):
    pins = {p.name(): p for p in cell.sub("pin")}
    outs = [n for n, p in pins.items() if p.attrs.get("direction") == "output"]
    ins = [n for n, p in pins.items() if p.attrs.get("direction") == "input"]
    seq = bool(cell.sub("ff") or cell.sub("latch"))
    for o in outs:
        body = re.sub(r"\b%s\b" % o, o + "_i", body)
    if seq:
        for i in ins:
            body = re.sub(r"\b%s\b" % i, i + "_d", body)
    lines = ["`celldefine", "module %s(%s);" % (cell.name(), header.rstrip()), ""]
    lines += ["wire %s_i;" % o for o in outs]
    if seq:                                       # see the module docstring: CVC MIPD bypass
        lines += ["wire %s;" % ", ".join(i + "_d" for i in ins)]
        lines += ["assign %s_d = %s;" % (i, i) for i in ins]
    lines.append(body.strip("\n"))
    lines += ["buf b_%s (%s, %s_i);" % (o, o, o) for o in outs]
    spec, checks = [], []
    clocked = {}                                  # clock pin -> edge of the capturing arcs
    for o in outs:
        func = pins[o].attrs.get("function", "")
        arcs = {}
        for t in pins[o].sub("timing"):
            rp, tt = t.attrs.get("related_pin"), t.attrs.get("timing_type", "combinational")
            arcs.setdefault((rp, tt), []).append(t.attrs.get("timing_sense", ""))
        for (rp, tt), senses in arcs.items():
            if tt == "combinational":
                if len(senses) == 2 and set(senses) == {"positive_unate", "negative_unate"}:
                    cp, cn = unate_conds(func, ins, rp)
                    order = {"positive_unate": cp, "negative_unate": cn}
                    for s in senses:                  # Liberty order = OpenSTA SDF order
                        spec.append("  if (%s) (%s => %s) = (0, 0);" % (order[s], rp, o))
                elif len(senses) == 1:
                    spec.append("  (%s => %s) = (0, 0);" % (rp, o))
                else:
                    raise SystemExit("%s %s->%s: unhandled senses %s" % (cell.name(), rp, o, senses))
            elif tt in ("rising_edge", "falling_edge"):
                edge = "posedge" if tt == "rising_edge" else "negedge"
                spec.append("  (%s %s => (%s : 1'bx)) = (0, 0);" % (edge, rp, o))
            else:
                raise SystemExit("%s: unhandled arc type %s" % (cell.name(), tt))
    for n, p in pins.items():
        if n not in ins:
            continue
        cons = {}
        for t in p.sub("timing"):
            tt = t.attrs.get("timing_type", "")
            m = re.match(r"(setup|hold)_(rising|falling)$", tt)
            if m:
                cons.setdefault((t.attrs["related_pin"], m.group(2)), set()).add(m.group(1))
            elif tt:
                raise SystemExit("%s/%s: unhandled check %s" % (cell.name(), n, tt))
        for (rp, e), kinds in cons.items():
            if kinds != {"setup", "hold"}:
                raise SystemExit("%s/%s: setup without hold" % (cell.name(), n))
            edge = "posedge" if e == "rising" else "negedge"
            clocked[rp] = edge
            for de in ("posedge", "negedge"):
                checks.append("  $setuphold(%s %s, %s %s, 0, 0, notifier);" % (edge, rp, de, n))
        if "min_pulse_width_high" in p.attrs:
            checks.append("  $width(posedge %s, 0, 0, notifier);" % n)
        if "min_pulse_width_low" in p.attrs:
            checks.append("  $width(negedge %s, 0, 0, notifier);" % n)
    for ff in cell.sub("ff"):
        for key in ("clear", "preset"):
            if key not in ff.attrs:
                continue
            m = re.fullmatch(r"\(?!(\w+)\)?", ff.attrs[key].replace(" ", ""))
            if not m:
                raise SystemExit("%s: unhandled %s %s" % (cell.name(), key, ff.attrs[key]))
            for clk, edge in clocked.items():
                checks.append("  $recrem(posedge %s, %s %s, REC, REM, notifier);" % (m.group(1), edge, clk))
    if seq and checks:
        # the notifier is read through a continuous assign: a procedural event control directly on
        # a timing-check notifier crashes CVC compiled code (SIGSEGV in __asl_trigger_ectrl, from
        # __process_all_tchk_violations), seen on the SRAM model and on a flop setup violation
        lines += ["reg notifier;", "wire notifier_w;", "assign notifier_w = notifier;",
                  "`ifndef MQ_TCHK_PROBE", "always @(notifier_w) state <= 1'bx;", "`endif"]
    if spec or checks:
        lines.append("specify")
        if any("REC" in c for c in checks):
            lines.append("  specparam REC = %.3f, REM = %.3f;   // placeholders: no Liberty arcs" % (REC_NS, REM_NS))
        lines += spec + checks + ["endspecify"]
    lines += ["endmodule", "`endcelldefine", ""]
    return "\n".join(lines)


def main():
    lib_path, v_path, out_path = sys.argv[1:4]
    lib = liberty.parse(lib_path)
    with open(v_path) as f:
        mods = split_modules(f.read())
    out = ["// GENERATED by src_int8/flow/sdf_gls/models/gen_cells.py from", "//   %s" % lib_path, "//   %s" % v_path,
           "`timescale 1ns/1ps", ""]
    cells = {c.name(): c for c in lib.sub("cell")}
    for name, (hdr, body) in mods.items():
        if name in cells:
            out.append(cell_model(cells[name], hdr, body))
        elif re.search(r"\boutput\b", hdr):
            raise SystemExit("%s has outputs but no Liberty cell" % name)
        else:                                     # tap_2: physical only, not in the Liberty
            out.append("module %s(%s);%sendmodule\n" % (name, hdr, body))
    with open(out_path, "w") as f:
        f.write("\n".join(out))
    print("gen_cells: %d cells -> %s" % (len(mods), out_path))


if __name__ == "__main__":
    main()
