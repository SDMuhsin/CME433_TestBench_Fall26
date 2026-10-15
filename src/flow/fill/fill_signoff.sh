#!/usr/bin/env bash
# LibreLane's own Magic DRC + Magic extraction/Netgen LVS re-run on the FILLED GDS of run <TAG>
# (fill.sh output), as a new run <TAG>_fillsignoff:
#   Magic.DRC (MAGIC_DRC_USE_GDS, the filled GDS) -> Checker.MagicDRC
#   Magic.SpiceExtraction with MAGIC_EXT_USE_GDS=true (extract the filled GDS, not the DEF)
#   -> Checker.IllegalOverlap -> Netgen.LVS (vs final pnl) -> Checker.LVS
# Magic loads MetalN dummy (N/4) as the non-electrical fillmN types, so extraction ignores the
# fill; the short/floating proof is check_fill.py. This run shows the filled GDS itself is
# Magic-DRC clean and extracts to the same netlist.
#   src/flow/fill/fill_signoff.sh <TAG> [GDS]   (GDS default runs/<TAG>/final/gds_filled/mb_chip.gds)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FLOW=$(cd "$HERE/.." && pwd)
TAG=${1:?usage: fill_signoff.sh <TAG> [GDS]}
RUN=$FLOW/runs/$TAG
GDS=$(realpath "${2:-$RUN/final/gds_filled/mb_chip.gds}")
OUTTAG=${OUTTAG:-${TAG}_fillsignoff}
STATE=$(ls "$RUN"/*-misc-reportmanufacturability/state_out.json)
cd "$FLOW"
librelane "$FLOW/config.yaml" --run-tag "$OUTTAG" --overwrite -i "$STATE" \
    --from Magic.DRC --to Checker.LVS -c MAGIC_EXT_USE_GDS=true -e gds="$GDS"
echo "Done: $FLOW/runs/$OUTTAG"
