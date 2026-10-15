#!/usr/bin/env python3
"""Add the dummy-metal squares to the routed database as one GROUNDED special net, for an
upper-bound parasitic extraction with fill (OpenRCX has no floating-conductor model; fill tied to
ground couples more than the real floating fill, so the resulting delays are pessimistic).

    openroad-librelane -no_init -exit -python fill_odb.py <in.odb> <fill.txt> <out.odb> <out.def>
"""
import sys
import odb

src, rects, out_odb, out_def = sys.argv[1:5]
db = odb.dbDatabase.create()
odb.read_db(db, src)
block = db.getChip().getBlock()
tech = db.getTech()
dbu = block.getDbUnitsPerMicron()
if block.findNet("FILL_GND") is not None:
    sys.exit("fill_odb.py: FILL_GND already present")
net = odb.dbNet.create(block, "FILL_GND")
net.setSpecial()
net.setSigType("GROUND")
net.setWildConnected()
sw = odb.dbSWire.create(net, "ROUTED")
try:
    ws = odb.dbWireShapeType("DRCFILL")
except Exception:
    ws = "DRCFILL"
layers = {}
n = 0
for line in open(rects):
    name, *v = line.split()
    lay = layers.setdefault(name, tech.findLayer(name))
    x1, y1, x2, y2 = (int(round(float(c) * dbu)) for c in v)
    odb.dbSBox.create(sw, lay, x1, y1, x2, y2, ws)
    n += 1
odb.write_db(db, out_odb)
odb.write_def(block, out_def)
print(f"fill_odb.py: {n} fill squares on FILL_GND -> {out_odb}, {out_def}")
