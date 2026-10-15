#!/usr/bin/env bash
# Unit test: latch RF vs the GF180 SRAM behavioural model (iverilog).
#   src_int8_tsmc65/sim/unit/run_rf_unit.sh [cycles] [build_dir]
set -eu
T65=$(cd "$(dirname "$0")/../.." && pwd)
ROOT=$(dirname "$T65")
N=${1:-200000}
OUT=${2:-$T65/sim/build/unit}
mkdir -p "$OUT"
iverilog -g2012 -Wall -s tb_rf_vs_sram -o "$OUT/tb_rf.vvp" \
    "$T65/rtl_mem/mq65_icg.v" "$T65/rtl_mem/mq65_latch_rf.v" \
    "$ROOT/src_int8/rtl/mem/gf180_sram_macro.v" "$T65/sim/unit/tb_rf_vs_sram.sv"
vvp -n "$OUT/tb_rf.vvp" "+N=$N" | tee "$OUT/tb_rf.log" | tail -3
grep -q '^PASS' "$OUT/tb_rf.log"
