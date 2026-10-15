#!/usr/bin/env bash
# Dump per-instance power for mq_chip (INT8, SDF + zero-delay SAIF) and mb_chip (FP16) at nom_tt
# into $OUT (default src_int8/analysis/build/power, git-ignored). Read-only on runs/ and build/power.
#   src_int8/analysis/power/run_power_instances.sh        (sources flow/env.sh itself)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../.." && pwd)
ROOT=$(dirname "$SRC")
source "$SRC/flow/env.sh"
OUT=${OUT:-$SRC/analysis/build/power}
mkdir -p "$OUT"
C=nom_tt_025C_3v30
TCL=$HERE/power_instances.tcl
RUN=$SRC/flow/runs/mq_final CORNER=$C OUT=$OUT TAG=mq.saif SCOPE=tb_mq_chip_sdf/dut \
  SAIF=$SRC/flow/build/power/$C.power.saif FLOWCOMMON=$SRC/flow/common \
  sta -no_splash -exit "$TCL" > "$OUT/sta.mq.saif.log" 2>&1 &
RUN=$SRC/flow/runs/mq_final CORNER=$C OUT=$OUT TAG=mq.zd SCOPE=tb_mq_chip_sdf/dut \
  SAIF=$SRC/flow/build/power/$C.power_zd.saif FLOWCOMMON=$SRC/flow/common \
  sta -no_splash -exit "$TCL" > "$OUT/sta.mq.zd.log" 2>&1 &
SCOPE_MB=$(grep -o 'tb_mb_chip_sdf/dut' "$ROOT/src/flow/power/report/power.tcl" | head -1); SCOPE_MB=${SCOPE_MB:-tb_mb_chip_sdf/dut}
RUN=$ROOT/src/flow/runs/mb_final CORNER=$C OUT=$OUT TAG=mb.saif SCOPE=$SCOPE_MB \
  SAIF=$ROOT/src/flow/build/power/$C.power.saif FLOWCOMMON=$ROOT/src/flow/common \
  sta -no_splash -exit "$TCL" > "$OUT/sta.mb.saif.log" 2>&1 &
wait; ls -la "$OUT"; tail -2 "$OUT"/sta.*.log
