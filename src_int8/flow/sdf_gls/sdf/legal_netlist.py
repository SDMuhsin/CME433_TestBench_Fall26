#!/usr/bin/env python3
"""Netlist copy for the CVC timing GLS: escaped INSTANCE names -> common/names.legal_name().

Only instance declarations are renamed (`<cell> \\esc.name  (`, in mq_chip only the 11 SRAM
macros); nets keep their names, so VCD/SAIF activity still maps onto the signoff netlist/SPEF.
usage: legal_netlist.py <in.v> <out.v>
"""
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "common"))
from names import legal_name  # noqa: E402

src, dst = sys.argv[1:3]
inst = re.compile(r"^(\s*\w+\s+)\\(\S+)(\s+\()")
n = 0
with open(src) as f, open(dst, "w") as g:
    for line in f:
        m = inst.match(line)
        if m:
            line = m.group(1) + legal_name(m.group(2)) + m.group(3) + line[m.end():]
            n += 1
        g.write(line)
print("legal_netlist: %d escaped instance names renamed -> %s" % (n, dst))
