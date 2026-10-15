#!/usr/bin/env bash
# Parasitic impact of the metal fill: re-extract (OpenRCX, nom/min/max) and re-run the 9-corner
# signoff STA of run <TAG> with the fill squares added to the routed database as a GROUNDED special
# net (FILL_GND; upper bound: real fill floats). Same LibreLane steps and config as build.sh step 4.
#   src/flow/fill/fill_sta.sh <TAG>      (after fill.sh)  -> new run src/flow/runs/<TAG>_fillrc
#   python3 src/flow/report/report.py <TAG> <TAG>_fillrc ; python3 -I src/flow/fill/rc/spef_delta.py <TAG> <TAG>_fillrc
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FLOW=$(cd "$HERE/.." && pwd)
TAG=${1:?usage: fill_sta.sh <TAG>}
RUN=$FLOW/runs/$TAG
GDS=$RUN/final/gds_filled/mb_chip.gds
RC=$RUN/fill/rc
[ -f "$GDS" ] || { echo "missing $GDS (run fill/fill.sh $TAG first)"; exit 2; }
mkdir -p "$RC"
python3 -I "$HERE/rc/export_fill.py" "$GDS" "$RC/fill_rects.txt"
openroad-librelane -no_init -exit -python "$HERE/rc/fill_odb.py" \
    "$RUN/_connected.odb" "$RC/fill_rects.txt" "$RC/_connected_fill.odb" "$RC/_connected_fill.def"
STATE=$(ls "$RUN"/*-misc-reportmanufacturability/state_out.json)   # state entering OpenROAD.RCX
cd "$FLOW"
librelane "$FLOW/config.yaml" --run-tag "${TAG}_fillrc" --overwrite -i "$STATE" \
    --from OpenROAD.RCX --to OpenROAD.STAPostPNR \
    -e odb="$RC/_connected_fill.odb" -e def="$RC/_connected_fill.def"
echo "Done: $FLOW/runs/${TAG}_fillrc"
