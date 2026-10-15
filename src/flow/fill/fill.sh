#!/usr/bin/env bash
# Metal fill + fill signoff for a finished run (after build.sh and kdrc.sh):
#   1) gen/fill.py    final/gds/mb_chip.gds -> final/gds_filled/mb_chip.gds (Metal1-5 dummy, DRM 13.3)
#   2) checks/check_fill.py XOR vs the unfilled GDS = 0, fill floating, DM.1/2b/3/4-7/8 coded on drawn metal
#   3) checks/density.py    block coverage, unfilled vs filled (whole area + 200 um windows)
#   4) checks/die_model.py  A56/ACV padring + block, rest of the die empty -> foundry density.drc + density.py
#   5) checks/dummy_drc.sh  the PDK dummy-metal decks DM1-DM5
#   6) drc/kdrc.sh    full foundry KLayout DRC (main, antenna, density, Vn.2b) on the filled GDS
#
#   src/flow/fill/fill.sh <TAG>        reports in src/flow/runs/<TAG>/fill/, DRC in runs/<TAG>/kdrc_filled/
# Needs the nix shell (source src/flow/env.sh). ~12 min. Exit 0 = steps 2, 5, 6 clean.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FLOW=$(cd "$HERE/.." && pwd)
TAG=${1:?usage: fill.sh <TAG>}
RUN=$FLOW/runs/$TAG
SRC=$RUN/final/gds/mb_chip.gds
DST=$RUN/final/gds_filled/mb_chip.gds
OUT=$RUN/fill
[ -f "$SRC" ] || { echo "missing $SRC"; exit 2; }
KPY=${KPY:-$("$FLOW/drc/setup.sh" | tail -1)} || { echo "drc/setup.sh failed"; exit 2; }
DECK=$PDK_ROOT/gf180mcuD/libs.tech/klayout/tech/drc
mkdir -p "$OUT" "$(dirname "$DST")"
rc=0
t0=$(date +%s)

python3 -I "$HERE/gen/fill.py" "$SRC" "$DST" >"$OUT/fill.log" 2>&1 || { cat "$OUT/fill.log"; exit 2; }
python3 -I "$HERE/checks/check_fill.py" "$SRC" "$DST" >"$OUT/check.txt" 2>&1 || rc=1
python3 -I "$HERE/checks/density.py" "$SRC" "$DST" >"$OUT/density.txt" 2>&1
python3 -I "$HERE/checks/die_model.py" "$SRC" "$OUT/die_unfilled.gds" >"$OUT/die_model.log" 2>&1
python3 -I "$HERE/checks/die_model.py" "$DST" "$OUT/die_filled.gds" >>"$OUT/die_model.log" 2>&1
python3 -I "$HERE/checks/density.py" "$OUT/die_unfilled.gds" "$OUT/die_filled.gds" >"$OUT/die_density.txt" 2>&1
rm -rf "$OUT/die_dens" "$OUT/dummy"
(cd "$DECK" && $KPY run_drc.py --path="$OUT/die_filled.gds" --variant=D --topcell=die_model \
    --run_dir="$OUT/die_dens" --density_only >"$OUT/die_dens.log" 2>&1)
"$HERE/checks/dummy_drc.sh" "$DST" "$OUT/dummy" >/dev/null || rc=1
KDRC_GDS=$DST KDRC_OUT=$RUN/kdrc_filled KPY=$KPY "$FLOW/drc/kdrc.sh" "$TAG" >/dev/null || rc=1

{
  echo "fill $TAG ($(( $(date +%s) - t0 )) s): $DST"
  grep -E "squares" "$OUT/fill.log"
  tail -1 "$OUT/check.txt"
  echo "PDK dummy decks: $(tail -1 "$OUT/dummy/dm_counts.txt") items"
  cat "$RUN/kdrc_filled/summary.txt"
  echo "die model density.drc: $(python3 -I "$HERE/checks/lyrdb_count.py" "$OUT"/die_dens/*.lyrdb | tr '\n' ' ')"
} | tee "$OUT/summary.txt"
exit $rc
