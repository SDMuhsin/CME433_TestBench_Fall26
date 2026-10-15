#!/usr/bin/env bash
# Chip-level regression of mq_chip with the 65 nm latch-RF memory layer: the unchanged
# src_int8 chip TB (tb_mq_chip.sv, pad-level QSPI host, golden vectors from the trained
# params) on rtl_mem/chip65.f instead of the GF180 SRAM wrapper + macro model.
#   src_int8_tsmc65/sim/chip/run_chip_rf.sh [--iv] [build_dir]
#     default Verilator (fast); --iv uses iverilog
# Prints the TB summary; exit 0 only on PASS (every logit / state byte bit-exact).
set -u
T65=$(cd "$(dirname "$0")/../.." && pwd)
ROOT=$(dirname "$T65")
SRC=$ROOT/src_int8
USE_IV=0; OUT=$T65/sim/build/chip
for a in "$@"; do
    case "$a" in --iv) USE_IV=1 ;; *) OUT=$a ;; esac
done
mkdir -p "$OUT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3
cd "$ROOT"
$PY -m src_int8.golden.vectors "$OUT/vec" --chip-only >"$OUT/vectors.log" 2>&1 ||
    { echo "FAIL: vector generation (see $OUT/vectors.log)"; exit 1; }
VEC=$OUT/vec/chip
RTL=$(sed -e '/^\/\//d' -e "s|^core/|$SRC/rtl/|" -e "s|^mem/|$T65/rtl_mem/|" "$T65/rtl_mem/chip65.f")
INC="-I$SRC/rtl/nonlin -I$SRC/rtl/seq -I$SRC/tb/common"
LOG=$OUT/tb_mq_chip.log
if [ $USE_IV -eq 1 ]; then
    iverilog -g2012 -s tb_mq_chip -o "$OUT/tb.vvp" $INC $RTL "$SRC/tb/chip/tb_mq_chip.sv" \
        2>"$OUT/compile.log" || { echo "FAIL: compile (see $OUT/compile.log)"; exit 1; }
    stdbuf -oL vvp -n "$OUT/tb.vvp" "+VEC=$VEC" >"$LOG"
else
    VL=${VERILATOR:-$(command -v verilator || ls -d /nix/store/*-verilator-5*/bin/verilator 2>/dev/null | head -1)}
    "$VL" --binary --timing -j 16 -Wno-fatal -Wno-lint -Wno-style $INC --top-module tb_mq_chip \
        -Mdir "$OUT/obj" -o "$OUT/tb_mq_chip" -CFLAGS -O2 $RTL "$SRC/tb/chip/tb_mq_chip.sv" \
        >"$OUT/build.log" 2>&1 || { echo "FAIL: verilator build (see $OUT/build.log)"; exit 1; }
    stdbuf -oL "$OUT/tb_mq_chip" "+VEC=$VEC" >"$LOG"
fi
grep -cE '^TOKEN' "$LOG" | sed 's/^/tokens reported: /'
grep -E '^(CYCLES|PASS|FAIL)' "$LOG" | tail -4
grep -q '^PASS' "$LOG"
