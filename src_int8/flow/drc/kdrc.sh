#!/usr/bin/env bash
# KLayout foundry DRC of a finished run's GDS (LibreLane 3.0.14 skips KLayout.DRC for gf180mcuD:
# KLAYOUT_DRC_RUNSET unset).  Same recipe as signoff/A56/klayout_drc and the FP16 signoff:
#   main  (FEOL+BEOL+connectivity+off-grid, variant D, deep)   -> must be 0
#   antenna (--antenna_only)                                   -> must be 0
#   density (--density_only)  whole-area coverage of the GDS bbox (M*.4/MT.3 >= 30 %, DCF.1b, PL.8)
#   Vn.2b via-array spacing (scripts/check_via_arrays.py)     -> must be 0
#
#   src_int8/flow/drc/kdrc.sh <TAG>        results in src_int8/flow/runs/<TAG>/kdrc/{main,ant,dens}/*.lyrdb + *.log
#   KDRC_GDS=<gds> KDRC_OUT=<dir> src_int8/flow/drc/kdrc.sh <TAG>   another GDS of the run (fill/fill.sh uses
#                                 this for final/gds_filled/mq_chip.gds -> runs/<TAG>/kdrc_filled)
# Needs the nix shell (source src_int8/flow/env.sh). The python env (klayout.db 0.30.7 + docopt 0.6.2) and
# the PDK/deck pins come from setup.sh in this dir (venv in drc/.venv, created on first use).
# env: SUMMARY_ONLY=1 re-summarise existing results; KPY = override the python (skips setup.sh)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FLOW=$(cd "$HERE/.." && pwd)
ROOT=$(cd "$FLOW/../.." && pwd)
TAG=${1:?usage: kdrc.sh <TAG>}
RUN=$FLOW/runs/$TAG
GDS=$(realpath "${KDRC_GDS:-$RUN/final/gds/mq_chip.gds}")   # absolute: the decks run from $DECK
OUT=${KDRC_OUT:-$RUN/kdrc}; mkdir -p "$OUT"; OUT=$(realpath "$OUT")
KPY=${KPY:-$("$HERE/setup.sh" | tail -1)} || { echo "drc/setup.sh failed"; exit 2; }
[ -n "$KPY" ] || { echo "drc/setup.sh failed"; exit 2; }
DECK=$PDK_ROOT/gf180mcuD/libs.tech/klayout/tech/drc
[ -f "$GDS" ] || { echo "missing $GDS"; exit 2; }
cd "$DECK"
if [ -z "${SUMMARY_ONLY:-}" ]; then
rm -rf "$OUT/main" "$OUT/ant" "$OUT/dens"   # stale .lyrdb would be counted below
t0=$(date +%s)
$KPY run_drc.py --path="$GDS" --variant=D --topcell=mq_chip --run_dir="$OUT/main" --run_mode=deep --thr=8 >"$OUT/main.log" 2>&1 &
$KPY run_drc.py --path="$GDS" --variant=D --topcell=mq_chip --run_dir="$OUT/ant" --antenna_only >"$OUT/ant.log" 2>&1 &
$KPY run_drc.py --path="$GDS" --variant=D --topcell=mq_chip --run_dir="$OUT/dens" --density_only >"$OUT/dens.log" 2>&1 &
$KPY "$ROOT/scripts/check_via_arrays.py" "$GDS" mq_chip >"$OUT/via.log" 2>&1 &
wait
echo "wall $(( $(date +%s) - t0 )) s" >"$OUT/time.txt"
fi
# run_drc.py exits 1 after --antenna_only/--density_only runs: count .lyrdb items instead.
n() { local f; f=$(ls "$OUT/$1"/*.lyrdb 2>/dev/null | head -1); if [ -n "$f" ]; then grep -c '<item>' "$f"; else echo missing; fi; }
main=$(n main); ant=$(n ant); dens=$(n dens)
via=$(grep -o 'VIOLATIONS=[0-9]*' "$OUT/via.log" | awk -F= '{s+=$2} END {print (NR ? s : "missing")}')
echo "KLayout DRC $TAG: main=$main antenna=$ant density=$dens (whole-area coverage, see README "Metal fill") Vn.2b=$via" | tee "$OUT/summary.txt"
[ "$main" = 0 ] && [ "$ant" = 0 ] && [ "$via" = 0 ]
