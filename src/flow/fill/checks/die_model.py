#!/usr/bin/env python3
"""Worst-case die model for the whole-die density rules: the A56/ACV padring + this block, and
NOTHING else (the other die area, i.e. the other projects' slots, the seal ring and any
integrator fill, is left empty, so every coverage figure is a lower bound for the real die).

    python3 -I die_model.py <block.gds> <out.gds> [--padring-def D] [--interface Y] [--io-gds G]

- padring: every COMPONENT of the auditor padring DEF (gf180mcu_fd_io cells, DEF N/S/E/W
  orientation, placement point = lower-left of the rotated LEF SIZE box from libs.ref lef/);
- block: the block GDS top cell at the interface YAML origin_microns (350, 1475 for A56/ACV);
- die boundary: the padring cfg AREA 2935 x 2935 um, drawn on 0/0 so the bbox is the die.
"""
import argparse
import os
import re
import klayout.db as db

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
ACV = os.path.join(ROOT, "layout_announcement/A56.def/A56/project_defs/ACV")
DIE_UM = 2935.0
ORIENT = {"N": db.DTrans.R0, "W": db.DTrans.R90, "S": db.DTrans.R180, "E": db.DTrans.R270}


def lef_box(cell, lef_dir):
    """LEF SIZE box (ORIGIN 0 0) of an IO cell; the GDS bbox overhangs it by 0.16 um."""
    t = open(os.path.join(lef_dir, f"{cell.name}.lef")).read()
    w, h = re.search(r"SIZE\s+([\d.]+)\s+BY\s+([\d.]+)", t).groups()
    return db.DBox(0, 0, float(w), float(h))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("block")
    ap.add_argument("out")
    ap.add_argument("--padring-def", default=os.path.join(ACV, "A56_ACV_padring.def"))
    ap.add_argument("--interface", default=os.path.join(ACV, "A56_ACV_interface.yaml"))
    pdk = os.environ.get("PDK_ROOT", "/root/.ciel-chipathon")
    ap.add_argument("--io-gds", default=f"{pdk}/gf180mcuD/libs.ref/gf180mcu_fd_io/gds/gf180mcu_fd_io.gds")
    a = ap.parse_args()
    lef_dir = os.path.join(os.path.dirname(os.path.dirname(a.io_gds)), "lef")

    ly = db.Layout()
    ly.read(a.io_gds)
    io_cells = {c.name: c for c in ly.each_cell()}
    die = ly.create_cell("die_model")

    text = open(a.padring_def).read()
    units = float(re.search(r"UNITS DISTANCE MICRONS (\d+)", text).group(1))
    comps = re.findall(r"-\s+(\S+)\s+(gf180mcu_fd_io__\w+)\s*\n\s*\+\s*PLACED\s*\(\s*(\d+)\s+(\d+)\s*\)\s*([NSEW])", text)
    for _, cname, x, y, o in comps:
        c = io_cells[cname]
        t = db.DTrans(ORIENT[o], db.DVector())
        bb = t * lef_box(c, lef_dir)
        disp = db.DVector(int(x) / units - bb.left, int(y) / units - bb.bottom)
        die.insert(db.DCellInstArray(c.cell_index(), db.DTrans(ORIENT[o], disp)))

    m = re.search(r"origin_microns:\s*\n-\s*'?([\d.]+)'?\s*\n-\s*'?([\d.]+)'?", open(a.interface).read())
    ox, oy = float(m.group(1)), float(m.group(2))
    blk = db.Layout()
    blk.read(a.block)
    btop = blk.top_cell()
    if blk.dbu != ly.dbu:
        raise SystemExit("dbu mismatch")
    holder = ly.create_cell(btop.name)
    holder.copy_tree(btop)  # copies the block hierarchy (cell names may get suffixes on clashes)
    die.insert(db.DCellInstArray(holder.cell_index(), db.DTrans(db.DVector(ox, oy))))
    die.shapes(ly.layer(0, 0)).insert(db.DBox(0, 0, DIE_UM, DIE_UM))
    for c in [c for c in ly.top_cells() if c.cell_index() != die.cell_index()]:
        c.prune_cell()  # unused IO library cells
    ly.write(a.out)
    print(f"die_model.py: {len(comps)} padring cells, block {btop.name} at ({ox}, {oy}), "
          f"die bbox {die.dbbox()} -> {a.out}")


if __name__ == "__main__":
    main()
