#!/usr/bin/env bash
# Verilator build of the benchmark TB (bench/tb/gan65_bench_tb.sv) around the full gan65_chip RTL
# (rtl/gan65.f) with the multiplier rtl/pe/gan_mul8.v replaced by a variant.
#   src_gan_tsmc65/bench/build.sh <variant> <out_dir> [--latch-rf]
#   <variant>: see bench/variant.py (exact | <name> | mq:<name> | path)
#   default memory model: mem/dla_sram_1rw_256x8_sim.v (flip-flop array, fast);
#   --latch-rf: the synthesised latch RF (mem/gan65_*.v), ~100x slower to simulate
# Produces <out_dir>/gan65_bench_tb; skips the build when it is newer than every source.
set -eu
T65=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$T65")
VAR=$1; mkdir -p "$2"; OUT=$(realpath "$2"); MEM=${3:-}
PY=${PYTHON:-python3}
VL=${VERILATOR:-$(command -v verilator || ls -d /nix/store/*-verilator-5*/bin/verilator 2>/dev/null | head -1)}
[ -x "$VL" ] || { echo "FAIL: no verilator found (set VERILATOR=...)"; exit 1; }
MUL=$(cd "$ROOT" && $PY -m src_gan_tsmc65.bench.variant "$VAR") || exit 1
RTL=$(sed -e '/^\/\//d' -e '/^pe\/gan_mul8\.v$/d' -e "s|^|$T65/rtl/|" "$T65/rtl/gan65.f")
if [ "$MEM" != --latch-rf ]; then
    RTL="$(echo "$RTL" | grep -v '/rtl/mem/') $T65/rtl/mem/dla_sram_1rw_256x8_sim.v"
fi
TB=$T65/bench/tb/gan65_bench_tb.sv
BIN=$OUT/gan65_bench_tb
if [ -x "$BIN" ] && echo "$MUL" | cmp -s - "$OUT/mul8_sources.txt" && echo "$RTL" | cmp -s - "$OUT/rtl_sources.txt" &&
   [ -z "$(find $RTL $MUL "$TB" -newer "$BIN" 2>/dev/null)" ]; then
    echo "up to date: $BIN"; exit 0
fi
echo "$MUL" > "$OUT/mul8_sources.txt"
echo "$RTL" > "$OUT/rtl_sources.txt"
"$VL" --binary --timing -j 16 -O3 -Wno-fatal -Wno-lint -Wno-style -I"$T65/rtl/seq" \
    --top-module gan65_bench_tb -Mdir "$OUT/obj" -o "$BIN" -CFLAGS "-O3 -march=native" \
    $RTL $MUL "$TB" >"$OUT/build.log" 2>&1 || { echo "FAIL: verilator build (see $OUT/build.log)"; exit 1; }
echo "built $BIN with $(echo $MUL | tr '\n' ' ')"
