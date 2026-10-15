#!/usr/bin/env python3
"""Per-rule item counts of a KLayout .lyrdb; for the dummy decks' DMn.3 rule also splits the
markers into those whose circuit-side edge lies on DRAWN MetalN and dummy-to-dummy pairs.

    python3 -I lyrdb_count.py <report.lyrdb> [<gds>]
"""
import re
import sys
import klayout.db as db
import klayout.rdb as rdb

DRAWN = {"1": (34, 0), "2": (36, 0), "3": (42, 0), "4": (46, 0), "5": (81, 0)}


def main():
    r = rdb.ReportDatabase("")
    r.load(sys.argv[1])
    ly = None
    if len(sys.argv) > 2:
        ly = db.Layout()
        ly.read(sys.argv[2])
    total = 0
    for cat in r.each_category():
        n = cat.num_items()
        total += n
        line = f"{cat.name()}: {n}"
        m = re.fullmatch(r"DM(\d)\.3", cat.name())
        if m and n and ly is not None:
            top = ly.top_cell()
            drawn = db.Region(top.begin_shapes_rec(ly.find_layer(*DRAWN[m.group(1)])))
            edges = db.Edges()
            for it in r.each_item_per_category(cat.rdb_id()):
                for v in it.each_value():
                    if v.is_edge_pair():
                        edges.insert(v.edge_pair().second.to_itype(ly.dbu))
            real = edges.interacting(drawn).count()
            line += f" (dummy-to-drawn: {real}, dummy-to-dummy: {n - real})"
        print(line)
    print(f"total: {total}")


if __name__ == "__main__":
    main()
