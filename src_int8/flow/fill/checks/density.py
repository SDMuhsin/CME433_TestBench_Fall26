#!/usr/bin/env python3
"""Metal/COMP/Poly2 coverage of a GDS: whole-die (the foundry density.drc rules) and the
200 x 200 um window / 100 um step check from the AS 3V3 tech LEF (MINIMUMDENSITY 30).

    python3 density.py <gds> [<gds> ...]      (needs klayout.db, e.g. the LibreLane nix python3)

Coverage = merged area of (drawn + dummy) / area of the top cell bbox, as in density.drc.
Windows are clipped to the bbox (the last row/column is shifted inward to end on the edge).
"""
import sys
import klayout.db as db

# name, drawn, dummy, whole-die rule, min %
LAYERS = [
    ("COMP", (22, 0), (22, 4), "DCF.1b", 25.0),
    ("Poly2", (30, 0), (30, 4), "PL.8", 14.0),
    ("Metal1", (34, 0), (34, 4), "M1.4", 30.0),
    ("Metal2", (36, 0), (36, 4), "M2.4", 30.0),
    ("Metal3", (42, 0), (42, 4), "M3.4", 30.0),
    ("Metal4", (46, 0), (46, 4), "M4.4", 30.0),
    ("Metal5", (81, 0), (81, 4), "M5.4/MT.3", 30.0),
]
WIN, STEP = 200.0, 100.0


def region(ly, top, ld):
    li = ly.find_layer(*ld)
    if li is None:
        return db.Region()
    return db.Region(top.begin_shapes_rec(li))


def starts(lo, hi):
    s, x = [], lo
    while x + WIN < hi:
        s.append(x)
        x += STEP
    s.append(hi - WIN)
    return s


def report(path):
    ly = db.Layout()
    ly.read(path)
    top = ly.top_cell()
    bb = top.bbox()
    dbu = ly.dbu
    chip = bb.area() * dbu * dbu
    wins = [db.Box(int(round(x / dbu)), int(round(y / dbu)),
                   int(round((x + WIN) / dbu)), int(round((y + WIN) / dbu)))
            for x in starts(bb.left * dbu, bb.right * dbu)
            for y in starts(bb.bottom * dbu, bb.top * dbu)]
    print(f"{path}  top={top.name}  bbox={top.dbbox()}  {len(wins)} windows {WIN:.0f}/{STEP:.0f} um")
    print(f"  {'layer':7} {'rule':10} {'drawn%':>7} {'dummy%':>7} {'total%':>7} {'min':>4} "
          f"{'die':4} {'win_min%':>8} {'win<30':>6}")
    worst = True
    for name, dr, du, rule, lim in LAYERS:
        rd, ru = region(ly, top, dr), region(ly, top, du)
        tot = (rd + ru).merged()
        a_d = rd.merged().area() * dbu * dbu / chip * 100
        a_u = ru.merged().area() * dbu * dbu / chip * 100
        a_t = tot.area() * dbu * dbu / chip * 100
        ok = a_t >= lim
        worst &= ok
        line = f"  {name:7} {rule:10} {a_d:7.2f} {a_u:7.2f} {a_t:7.2f} {lim:4.0f} {'ok' if ok else 'LOW':4}"
        if name.startswith("Metal"):
            dens = [(tot & db.Region(w)).area() / w.area() * 100 for w in wins]
            line += f" {min(dens):8.2f} {sum(d < 30.0 for d in dens):6d}"
        print(line)
    print(f"  whole-die rules: {'all met' if worst else 'NOT met'}")
    return worst


if __name__ == "__main__":
    ok = all([report(p) for p in sys.argv[1:]])
    sys.exit(0 if ok else 1)
