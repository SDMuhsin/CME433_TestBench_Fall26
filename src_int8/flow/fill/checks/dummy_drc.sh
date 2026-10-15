#!/usr/bin/env bash
# PDK dummy-metal rule decks (DM1..DM5: DM.2b, DM.3, DM.4-DM.7, DM.8) on a filled GDS.
# run_drc.py never enables them (no --dummy switch; DUMMY_SUB_PREV is only defined in the
# monolithic gf180mcu.drc), so this assembles the deck the way run_drc.py does for one table:
#   main.drc + "DUMMY_SUB_PREV = true" + dummy_metal{1..5}.drc + tail.drc, layers_def.drc alongside,
# and runs it with run_drc.py's variant-D switches plus dummy=true. The PDK files are not edited.
#   fill/checks/dummy_drc.sh <gds> <out_dir>         -> <out_dir>/dummy.lyrdb, dummy.log, dm_counts.txt (exit 0 = 0 items)
# Known deck defect (verified with a 2-shape test layout, 2026-10-14): DMn.3 is coded as
# metalN_dummy.separation(metalN, 2 um) with metalN = drawn + dummy (layers_def.drc). The dummy's
# own copy inside metalN shields the check (KLayout shielding is on by default), so a dummy 1 um
# from drawn metal is NOT reported; only overlaps are. check_fill.py codes DM.3 against drawn
# metal directly and is the authoritative DM.3 check. DM.2b, DM.4-DM.7 and DM.8 work as coded.
set -euo pipefail
GDS=$(realpath "${1:?usage: dummy_drc.sh <gds> <out_dir>}")
OUT=${2:?usage: dummy_drc.sh <gds> <out_dir>}
mkdir -p "$OUT"; OUT=$(realpath "$OUT")
DECK=$PDK_ROOT/gf180mcuD/libs.tech/klayout/tech/drc/rule_decks
TOP=${TOP:-mq_chip}
cp "$DECK/layers_def.drc" "$OUT/layers_def.drc"
{
  cat "$DECK/main.drc"
  printf '\nDUMMY_SUB_PREV = true\nlogger.info("DUMMY_SUB_PREV enabled: #{DUMMY_SUB_PREV}")\n'
  for n in 1 2 3 4 5; do cat "$DECK/dummy_metal$n.drc"; done
  cat "$DECK/tail.drc"
} >"$OUT/dummy.drc"
klayout -b -r "$OUT/dummy.drc" \
  -rd input="$GDS" -rd topcell="$TOP" -rd report="$OUT/dummy.lyrdb" -rd table_name=dummy \
  -rd thr=8 -rd run_mode=deep -rd metal_top=11K -rd mim_option=B -rd metal_level=5LM \
  -rd verbose=false -rd feol=true -rd beol=true -rd offgrid=true -rd conn_drc=true \
  -rd density=false -rd split_deep=false -rd slow_via=false -rd dummy=true >"$OUT/dummy.log" 2>&1
python3 -I "$(dirname "$0")/lyrdb_count.py" "$OUT/dummy.lyrdb" "$GDS" | tee "$OUT/dm_counts.txt"
grep -q "^total: 0$" "$OUT/dm_counts.txt"
