#!/usr/bin/env python3
"""Checks that a filled GDS = the unfilled GDS + floating, DRM-legal dummy metal, nothing else.

    python3 -I check_fill.py <unfilled.gds> <filled.gds> [--edge 2.0]      exit 0 = all PASS

1. XOR: every layer except the MetalN dummy datatypes (34/36/42/46/81 : 4) is identical (flat
   XOR = 0); the dummy datatypes are empty in the unfilled GDS. The original cells keep their
   names and content; the only new cells are the <prefix>METALn_FILL / Metaln_fill_cell pairs.
2. Shapes: every dummy polygon is a 2.000 x 2.000 um square (DM.1).
3. Floating: no dummy square touches or overlaps same-layer circuit metal (N/0, label polygons
   and texts on N/10), a via/contact that lands on that layer, or the block boundary edge band.
4. DM rules, coded here against DRAWN metal (the PDK dummy decks compare DM.3 against
   drawn+dummy, which flags the PDK's own 1.2 um fill pitch; see dummy_drc.sh):
   DM.2b dummy-dummy space >= 0.98 um; DM.3 dummy-circuit >= 2.0 um; DM.4-DM.7 dummy to the
   drawn layer above/below >= 1.0 um and no overlap; DM.8 >= 6 um to the fuse/PMNDMY/MTP/OTP
   markers.
"""
import argparse
import klayout.db as db

STACK = [  # name, layer, below (metal or Poly2 for Metal1), above, vias touching the layer
    ("Metal1", 34, 30, 36, [(33, 0), (35, 0)]),
    ("Metal2", 36, 34, 42, [(35, 0), (38, 0)]),
    ("Metal3", 42, 36, 46, [(38, 0), (40, 0)]),
    ("Metal4", 46, 42, 81, [(40, 0), (41, 0)]),
    ("Metal5", 81, 46, None, [(41, 0), (82, 0)]),
]
MARKERS = [(75, 0), (220, 0), (96, 1), (152, 5), (122, 5), (173, 5)]
DUMMY = {(l, 4) for _, l, _, _, _ in STACK}


def load(path):
    ly = db.Layout()
    ly.read(path)
    return ly, ly.top_cell()


def reg(ly, top, l, d):
    li = ly.find_layer(l, d)
    return db.Region() if li is None else db.Region(top.begin_shapes_rec(li))


def texts(ly, top, l, d):
    li = ly.find_layer(l, d)
    return db.Texts() if li is None else db.Texts(top.begin_shapes_rec(li))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("unfilled")
    ap.add_argument("filled")
    ap.add_argument("--edge", type=float, default=2.0)
    ap.add_argument("--prefix", default="mq_chip_")
    a = ap.parse_args()
    la, ta = load(a.unfilled)
    lb, tb = load(a.filled)
    um = lambda v: int(round(v / lb.dbu))
    fails = []

    def check(name, n):
        print(f"  {'PASS' if n == 0 else 'FAIL'} {name}: {n}")
        if n:
            fails.append(name)

    print(f"check_fill.py: {a.unfilled} vs {a.filled}")
    # 1. XOR / structure
    layers = {(i.layer, i.datatype) for l in (la, lb) for i in (l.get_info(x) for x in l.layer_indexes())}
    xor = 0
    for l, d in sorted(layers - DUMMY):
        n = (reg(la, ta, l, d) ^ reg(lb, tb, l, d)).count()
        nt = abs(texts(la, ta, l, d).count() - texts(lb, tb, l, d).count())
        if n or nt:
            print(f"    XOR {l}/{d}: {n} polygons, {nt} texts")
        xor += n + nt
    check(f"XOR on {len(layers - DUMMY)} non-dummy layers", xor)
    check("dummy shapes already in the unfilled GDS",
          sum(reg(la, ta, l, d).count() for l, d in DUMMY))
    names_a = {c.name for c in la.each_cell()}
    names_b = {c.name for c in lb.each_cell()}
    expect = {f"{a.prefix}{n.upper()}_FILL" for n, *_ in STACK} | {f"{a.prefix}{n}_fill_cell" for n, *_ in STACK}
    check("original cells missing in the filled GDS", len(names_a - names_b))
    check("unexpected new cells", len((names_b - names_a) ^ expect))
    changed = 0
    for c in la.each_cell():
        cb = lb.cell(c.name)
        if cb is None:
            continue
        if c.name == ta.name:
            if cb.child_instances() != c.child_instances() + len(STACK):
                changed += 1
        elif cb.child_instances() != c.child_instances() or any(
                cb.shapes(lb.find_layer(la.get_info(li))).size() != c.shapes(li).size()
                for li in la.layer_indexes()):
            changed += 1
    check("original cells with changed shape/instance counts", changed)

    frame = db.Region(tb.bbox())
    band = frame - frame.sized(-um(a.edge))
    markers = db.Region()
    for l, d in MARKERS:
        markers += reg(lb, tb, l, d)
    drawn = {l: reg(lb, tb, l, 0) for _, l, *_ in STACK}
    drawn[30] = reg(lb, tb, 30, 0)
    for name, l, below, above, vias in STACK:
        dm = reg(lb, tb, l, 4)
        circ = drawn[l] + reg(lb, tb, l, 10)
        lbl = texts(lb, tb, l, 10) + texts(lb, tb, l, 0)
        via = db.Region()
        for v in vias:
            via += reg(lb, tb, *v)
        print(f"  {name}: {dm.count()} dummy squares")
        # 2. DM.1
        check(f"{name} DM.1 not a 2x2 um square",
              sum(1 for p in dm.each() if not (p.is_box() and p.bbox().width() == um(2) and p.bbox().height() == um(2))))
        # 3. floating
        check(f"{name} dummy touching circuit metal", dm.interacting(circ).count())
        check(f"{name} dummy touching via/contact", dm.interacting(via).count())
        check(f"{name} dummy touching labels", dm.interacting(lbl).count())
        check(f"{name} dummy in the {a.edge} um edge band", dm.overlapping(band).count())
        # 4. DM rules
        check(f"{name} DM.2b space < 0.98", dm.space_check(um(0.98), False, db.Metrics.Euclidian).count())
        check(f"{name} DM.3 to circuit < 2.0", dm.separation_check(circ, um(2.0), False, db.Metrics.Euclidian).count())
        adj = drawn[below] + (drawn[above] if above is not None else db.Region())
        check(f"{name} DM.4-7 to adjacent < 1.0",
              dm.separation_check(adj, um(1.0), False, db.Metrics.Euclidian).count() + (dm & adj).count())
        check(f"{name} DM.8 to markers < 6.0",
              dm.separation_check(markers, um(6.0), False, db.Metrics.Euclidian).count() + (dm & markers).count())
    print(f"check_fill.py: {'ALL PASS' if not fails else 'FAIL: ' + ', '.join(fails)}")
    raise SystemExit(1 if fails else 0)


if __name__ == "__main__":
    main()
