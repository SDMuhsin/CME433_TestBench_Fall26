#!/usr/bin/env python3
"""VCD of the flat mb_chip nets -> SAIF with one entry per instance pin (for OpenSTA).

OpenSTA's read_vcd / read_saif annotate PINS: a net-level VCD of a flat netlist annotates only the
62 top-level ports (the internal nets are not pins of the top instance).  This converter takes the
net VCD written by the SDF GLS ($dumpvars(1, tb_mb_chip_sdf.dut), every glitch the SDF timing
produces included), computes per net T0 / T1 / TX (ps) and TC (0<->1 transitions) over the
window, and writes them for every pin on the net: (INSTANCE <cell inst> (NET (<pin> ...))), plus
the top ports.  Nets are matched to pins with the signoff netlist (final/nl).  The entries are
written as NET (OpenSTA's SAIF reader looks every NET name up as a pin of the enclosing instance
and ignores PORT lists: "Annotated 0 pin activities").

usage: vcd2saif.py <vcd> <netlist.v> <out.saif> [--start-ps T] [--end-ps T] [--scope tb_mb_chip_sdf.dut]
Prints net / pin counts and the window; the window defaults to the first and last VCD time.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
from names import norm, saif_id  # noqa: E402
from netlist import parse_netlist  # noqa: E402


def scan_vcd(path, scope, start, end):
    ids = {}                                      # vcd id -> net name (only in `scope`)
    stack = []
    want = scope.split(".")
    f = open(path, "rb")
    for raw in f:
        line = raw.decode("ascii", "replace").strip()
        if line.startswith("$scope"):
            stack.append(line.split()[2])
        elif line.startswith("$upscope"):
            stack.pop()
        elif line.startswith("$var"):
            p = line.split()
            if stack == want:
                if p[2] != "1":
                    raise SystemExit("vector var %s not handled" % line)
                ids[p[3]] = norm(" ".join(p[4:-1]))
        elif line.startswith("$enddefinitions"):
            break
    val = {i: "x" for i in ids}
    last = {i: None for i in ids}
    t0 = {i: 0 for i in ids}
    t1 = {i: 0 for i in ids}
    tx = {i: 0 for i in ids}
    tc = {i: 0 for i in ids}
    now = None
    first = None

    def account(i, t):
        lt = last[i]
        if lt is None:
            return
        a, b = max(lt, start if start is not None else lt), t if end is None else min(t, end)
        if b > a:
            v = val[i]
            if v == "0":
                t0[i] += b - a
            elif v == "1":
                t1[i] += b - a
            else:
                tx[i] += b - a

    for raw in f:
        c = raw[:1]
        if c == b"#":
            now = int(raw[1:])
            if first is None:
                first = now
                if start is None:
                    start = now
            continue
        if c in (b"0", b"1", b"x", b"z", b"X", b"Z"):
            i = raw[1:].strip().decode()
            if i not in val:
                continue
            v = c.decode().lower()
            t = now if now is not None else 0
            account(i, t)
            old = val[i]
            if (end is None or t <= end) and t >= start and ((old == "0" and v == "1") or (old == "1" and v == "0")):
                tc[i] += 1
            val[i] = v
            last[i] = t
        # $dumpvars / $end / comments: nothing to do
    if end is None:
        end = now
    for i in ids:
        if last[i] is None:
            last[i] = start
        account(i, end)
    nets = {ids[i]: (t0[i], t1[i], tx[i], tc[i]) for i in ids}
    return nets, start, end


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("vcd")
    ap.add_argument("netlist")
    ap.add_argument("saif")
    ap.add_argument("--start-ps", type=int)
    ap.add_argument("--end-ps", type=int)
    ap.add_argument("--scope", default="tb_mb_chip_sdf.dut")
    a = ap.parse_args()
    ports, pins, _ = parse_netlist(a.netlist)
    nets, start, end = scan_vcd(a.vcd, a.scope, a.start_ps, a.end_ps)
    dur = end - start
    by_inst = {}
    miss_pins = 0
    for inst, pin, net in pins:
        if net not in nets:
            miss_pins += 1
            continue
        by_inst.setdefault(inst, []).append((pin, nets[net]))
    miss_ports = [p for p in ports if p not in nets]

    def ent(name, s):
        return "(%s (T0 %d) (T1 %d) (TX %d) (TC %d) (IG 0))" % (saif_id(name), s[0], s[1], s[2], s[3])

    with open(a.saif, "w") as g:
        g.write('(SAIFILE\n(SAIFVERSION "2.0")\n(DIRECTION "backward")\n(DESIGN )\n(PROGRAM_NAME "vcd2saif.py")\n'
                '(DIVIDER / )\n(TIMESCALE 1 ps)\n(DURATION %d)\n' % dur)
        g.write("(INSTANCE %s\n" % a.scope.split(".")[0])
        g.write("(INSTANCE %s\n" % a.scope.split(".")[1])
        g.write("(NET\n%s\n)\n" % "\n".join(ent(p, nets[p]) for p in ports if p in nets))
        for inst, lst in by_inst.items():
            g.write("(INSTANCE %s (NET %s))\n" % (saif_id(inst), " ".join(ent(p, s) for p, s in lst)))
        g.write(")\n)\n)\n")
    tc_tot = sum(s[3] for s in nets.values())
    print("vcd2saif: window %d .. %d ps (%.6f ms), %d nets (%d transitions, %.1f per clk of 40 ns), "
          "%d pins on %d instances, %d pins on nets not in the VCD, top ports missing %s -> %s"
          % (start, end, dur * 1e-9, len(nets), tc_tot, tc_tot / (dur / 40000.0), sum(len(v) for v in by_inst.values()),
             len(by_inst), miss_pins, miss_ports, a.saif))


if __name__ == "__main__":
    main()
