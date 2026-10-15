#!/usr/bin/env python3
"""Dump the dummy-metal squares of a filled GDS as text for fill_odb.py (openroad has no klayout).

    python3 -I export_fill.py <filled.gds> <out.txt>       lines: <MetalN> x1 y1 x2 y2   (um)
"""
import sys
import klayout.db as db

LAYERS = {34: "Metal1", 36: "Metal2", 42: "Metal3", 46: "Metal4", 81: "Metal5"}
ly = db.Layout()
ly.read(sys.argv[1])
top = ly.top_cell()
n = 0
with open(sys.argv[2], "w") as f:
    for l, name in LAYERS.items():
        li = ly.find_layer(l, 4)
        if li is None:
            continue
        for p in db.Region(top.begin_shapes_rec(li)).each():
            b = p.bbox().to_dtype(ly.dbu)
            f.write(f"{name} {b.left:.3f} {b.bottom:.3f} {b.right:.3f} {b.top:.3f}\n")
            n += 1
print(f"export_fill.py: {n} squares -> {sys.argv[2]}")
