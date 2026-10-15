#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------------
# Harden mb_chip to a power-connected, signed-off A56/ACV block (same 4-stage flow as
# librelane/build_fp16_connected.sh):
#   1) LibreLane synth -> floorplan -> place -> CTS -> route -> fill (stop before streamout)
#   2) weld the template DVDD/DVSS pins to the PDN core ring (librelane/connect_power.py)
#   3) resume: streamout -> Magic/KLayout DRC -> XOR -> LVS -> checkers
#   4) SPEF RCX + 9-corner STA on the connected design (signoff.sdc)
#
#   src/flow/build.sh <TAG> [extra librelane args, e.g. -c PL_TARGET_DENSITY_PCT=55]
# Needs librelane (3.0.14, --manual-pdk shim) and openroad-librelane on PATH (source env.sh).
# Output: src/flow/runs/<TAG>/ ; summary: python3 src/flow/report/report.py <TAG>
# ---------------------------------------------------------------------------------------------
set -euo pipefail
FLOW=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$FLOW/../.." && pwd)
TAG=${1:?usage: build.sh <TAG> [librelane args]}; shift
CFG=$FLOW/config.yaml
DESIGN=mb_chip
cd "$FLOW"

librelane "$CFG" --run-tag "$TAG" --to Odb.CellFrequencyTables "$@"

RUN=$FLOW/runs/$TAG
CLEAN_ODB=$(ls "$RUN"/*-odb-cellfrequencytables/$DESIGN.odb)   # pristine, pre-streamout
FILL=$(ls -d "$RUN"/*-openroad-fillinsertion)

openroad-librelane -no_init -exit -python "$ROOT/librelane/connect_power.py" \
    "$CLEAN_ODB" "$RUN/_connected.odb" "$RUN/_connected.def"

librelane "$CFG" --run-tag "$TAG" --from Magic.StreamOut "$@" \
    -e odb="$RUN/_connected.odb" \
    -e def="$RUN/_connected.def" \
    -e pnl="$(realpath "$FILL"/$DESIGN.pnl.v)" \
    -e nl="$(realpath "$FILL"/$DESIGN.nl.v)"

librelane "$CFG" --run-tag "$TAG" --from OpenROAD.RCX --to OpenROAD.STAPostPNR "$@"

echo "Done: $RUN/final (gds/def/nl/pnl/spef); signoff STA in $RUN/*-openroad-stapostpnr/"
