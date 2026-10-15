#!/usr/bin/env python3
"""Metal1..Metal5 dummy fill for mb_chip, to the GF180MCU DRM section 13.3 dummy-metal rules.

    python3 -I fill.py <in.gds> <out.gds> [--prefix mb_chip_] [--edge 2.0]

Pattern = the PDK filler (libs.tech/klayout/tech/drc/filler_generation/fill_metal.rb): 2 x 2 um
squares (DM.1, fixed size) on MetalN dummy (datatype 4), lattice (3.2, 0.5) / (0.5, 3.2) um
(DM.2a 1.2 um space, DM.10 0.5 um same-layer offset), origin (0.5(N-1), 0.5(N-1)) per layer (DM.9).
Keep-outs, measured from the 2 x 2 square:
  DM.3        2.0 um to circuit MetalN (drawn N/0 and label-layer polygons N/10)
  DM.4..DM.7  1.0 um to the metal layer above and below (Metal1: Poly2 below, as in the PDK
              script; Metal5 is the top layer of the 5LM stack, nothing above)
  DM.8        6.0 um to FuseTop, POLYFUSE, FUSEWINDOW_D, PMNDMY, MTPMK, OTP_MK
  macros      no fill on the layers an SRAM macro obstructs in its LEF (Metal1-3) inside its bbox
  edge        --edge um (default 2.0 = DM.3) inside the top-cell bbox, so the block's fill keeps
              DM.3 to whatever circuit metal the integrator places outside the block boundary
Differences from fill_metal.rb: DM.4-DM.7 at the DRM value 1 um (the PDK script uses 2 um or
nothing), no 26 um scribe-line ring (this GDS is a block, not a die), and up to four passes with
the lattice shifted by half a pitch to fill the slivers the first lattice cannot; every pass keeps
1.2 um (DM.2a) from the fill of the previous passes.
Fill goes into new cells <prefix>METALn_FILL (instances of <prefix>Metaln_fill_cell) under the top
cell. No existing cell or shape is changed (checked by check_fill.py).
"""
import argparse
import klayout.db as db

STACK = [  # name, layer, below, above
    ("Metal1", 34, 30, 36),
    ("Metal2", 36, 34, 42),
    ("Metal3", 42, 36, 46),
    ("Metal4", 46, 42, 81),
    ("Metal5", 81, 46, None),
]
MARKERS = [(75, 0), (220, 0), (96, 1), (152, 5), (122, 5), (173, 5)]  # DM.8
MACRO_LAYERS = {34, 36, 42}  # SRAM LEF OBS: Metal1, Metal2, Metal3
SQ, SPACE, SKEW = 2.0, 1.2, 0.5
PASS_SHIFT = [(0.0, 0.0), (1.6, 1.6), (1.6, 0.0), (0.0, 1.6)]


def rec(ly, top, l, d):
    li = ly.find_layer(l, d)
    return db.Region() if li is None else db.Region(top.begin_shapes_rec(li))


def lattice(ly, bbox, ox, oy):
    """All 2 x 2 um squares of the skewed lattice origin + i*(3.2, 0.5) + j*(0.5, 3.2) inside bbox
    (lower-left corners; integer DBU, so squares of one lattice never coincide)."""
    p, k = SQ + SPACE, SKEW
    det = p * p - k * k
    x0, y0, x1, y1 = (v * ly.dbu for v in (bbox.left, bbox.bottom, bbox.right, bbox.top))
    corners = [(x - ox, y - oy) for x in (x0, x1) for y in (y0, y1)]
    ij = [((p * cx - k * cy) / det, (p * cy - k * cx) / det) for cx, cy in corners]
    i0, i1 = int(min(c[0] for c in ij)) - 1, int(max(c[0] for c in ij)) + 1
    j0, j1 = int(min(c[1] for c in ij)) - 1, int(max(c[1] for c in ij)) + 1
    r = db.Region()
    s = um(ly, SQ)
    for i in range(i0, i1 + 1):
        for j in range(j0, j1 + 1):
            x, y = ox + i * p + j * k, oy + i * k + j * p
            if x0 <= x and x + SQ <= x1 and y0 <= y and y + SQ <= y1:
                xi, yi = um(ly, x), um(ly, y)
                r.insert(db.Box(xi, yi, xi + s, yi + s))
    return r


def um(ly, v):
    return int(round(v / ly.dbu))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("--prefix", default="mb_chip_")
    ap.add_argument("--edge", type=float, default=2.0)
    a = ap.parse_args()

    ly = db.Layout()
    ly.read(a.inp)
    top = ly.top_cell()
    frame = db.Region(top.bbox())
    for _, l, _, _ in STACK:
        if not rec(ly, top, l, 4).is_empty():
            raise SystemExit(f"fill.py: input already has dummy on {l}/4")

    markers = db.Region()
    for l, d in MARKERS:
        markers += rec(ly, top, l, d)
    macros = db.Region()
    for inst in top.each_inst():
        c = inst.cell
        if not c.name.startswith(a.prefix) and "sram" in c.name.lower():
            macros.insert(inst.bbox())
    print(f"fill.py: {a.inp} top={top.name} bbox={top.dbbox()} edge={a.edge} um "
          f"macros={macros.count()} markers={markers.count()}")

    core = frame.sized(-um(ly, a.edge)) - markers.sized(um(ly, 6.0))
    drawn = {l: rec(ly, top, l, 0) + rec(ly, top, l, 10) for _, l, _, _ in STACK}
    drawn[30] = rec(ly, top, 30, 0)
    for n, (name, l, below, above) in enumerate(STACK):
        allowed = core - drawn[l].sized(um(ly, 2.0)) - drawn[below].sized(um(ly, 1.0))
        if above is not None:
            allowed -= drawn[above].sized(um(ly, 1.0))
        if l in MACRO_LAYERS:
            allowed -= macros
        allowed.merge()

        dl = ly.layer(l, 4)
        fc = ly.create_cell(f"{a.prefix}{name}_fill_cell")
        fc.shapes(dl).insert(db.Box(0, 0, um(ly, SQ), um(ly, SQ)))
        holder = ly.create_cell(f"{a.prefix}{name.upper()}_FILL")
        top.insert(db.CellInstArray(holder.cell_index(), db.Trans()))
        o = 0.5 * n
        placed = db.Region()
        counts = []
        for dx, dy in PASS_SHIFT:
            cand = lattice(ly, top.bbox(), o + dx, o + dy)
            new = cand.inside(allowed)          # squares entirely inside the legal area
            for poly in new.each():
                bb = poly.bbox()
                holder.insert(db.CellInstArray(fc.cell_index(), db.Trans(bb.left, bb.bottom)))
            counts.append(new.count())
            placed += new
            allowed = (allowed - new.sized(um(ly, SPACE))).merged()
        print(f"  {name}: {sum(counts)} squares (passes {counts}), "
              f"{placed.area() * ly.dbu ** 2 / (frame.area() * ly.dbu ** 2) * 100:.2f} % of bbox")

    ly.write(a.out)
    print(f"fill.py: wrote {a.out}")


if __name__ == "__main__":
    main()
