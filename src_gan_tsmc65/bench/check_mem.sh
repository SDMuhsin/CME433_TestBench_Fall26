#!/usr/bin/env bash
# Unit equivalence of the 65 nm latch RF and the fast flip-flop simulation model (iverilog).
#   src_gan_tsmc65/bench/check_mem.sh [build_dir]
set -u
T65=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$(dirname "$T65")/build/gan65/check_mem}
mkdir -p "$OUT"
iverilog -g2012 -s tb_mem_equiv -o "$OUT/tb_mem_equiv.vvp" "$T65/rtl/mem/gan65_icg.v" \
    "$T65/rtl/mem/gan65_latch_rf.v" "$T65/bench/tb/tb_mem_equiv.sv" || { echo "FAIL: compile"; exit 1; }
vvp -n "$OUT/tb_mem_equiv.vvp" | tee "$OUT/tb_mem_equiv.log" | grep -E '^(PASS|FAIL|cycle)'
grep -q '^PASS' "$OUT/tb_mem_equiv.log"
