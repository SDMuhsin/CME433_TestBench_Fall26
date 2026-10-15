#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build the power-connected A56/ACV block GDS for the FP16 END-TO-END design
# dla_fp16_chip (config_fp16.yaml). Same 3-stage flow as build_acv_connected.sh
# (see that script for the rationale of the power-pin weld), plus the SPEF
# multi-corner STA resume at the end.
#
#   ./build_fp16_connected.sh <TAG> [extra librelane args, e.g. -c PL_TARGET_DENSITY_PCT=60]
#
# Run from librelane/ with librelane + openroad-librelane on PATH.
# ---------------------------------------------------------------------------
set -euo pipefail
TAG=${1:-fp16_connected}; shift || true
CFG=config_fp16.yaml
DESIGN=dla_fp16_chip

# 1) Synthesis -> placement -> CTS -> routing -> fill (stop before streamout).
librelane "$CFG" --run-tag "$TAG" --to Odb.CellFrequencyTables "$@"

RUN="runs/$TAG"
CLEAN_ODB=$(ls "$RUN"/*-odb-cellfrequencytables/$DESIGN.odb)   # pristine, pre-streamout
FILL=$(ls -d "$RUN"/*-openroad-fillinsertion)

# 2) Weld DVDD/DVSS template pins to the PDN ring (always from the PRISTINE odb).
openroad-librelane -no_init -exit -python connect_power.py \
    "$CLEAN_ODB" "$RUN/_connected.odb" "$RUN/_connected.def"

# 3) Resume: streamout -> DRC -> XOR -> LVS -> rest of signoff.
librelane "$CFG" --run-tag "$TAG" --from Magic.StreamOut "$@" \
    -e odb="$(realpath "$RUN/_connected.odb")" \
    -e def="$(realpath "$RUN/_connected.def")" \
    -e pnl="$(realpath "$FILL"/$DESIGN.pnl.v)" \
    -e nl="$(realpath "$FILL"/$DESIGN.nl.v)"

# 4) SPEF RCX + 9-corner STA on the connected design.
librelane "$CFG" --run-tag "$TAG" --from OpenROAD.RCX --to OpenROAD.STAPostPNR "$@"

echo "Done. Power-connected views in $RUN/final/ (gds/def/nl); SPEF STA in $RUN/*-openroad-stapostpnr/."
