#!/usr/bin/env bash
# Verilator build of the pipe-driven demo TB (tb_mb_demo.sv + the full mb_chip RTL, chip.f).
#   src/demo/tb/build_verilator.sh [out_dir]   (default src/demo/build/verilator)
# Produces <out_dir>/tb_mb_demo, a drop-in replacement for the iverilog image in ChipSim
# (same plusargs, same pipe protocol, same cycle counts); about 1 s per token instead of ~15 s.
# Verilator: $VERILATOR, else `verilator` on PATH, else the first Verilator 5 in /nix/store.
set -eu
SRC=$(cd "$(dirname "$0")/../.." && pwd)
OUT=${1:-$SRC/demo/build/verilator}
VL=${VERILATOR:-$(command -v verilator || ls -d /nix/store/*-verilator-5*/bin/verilator 2>/dev/null | head -1)}
[ -x "$VL" ] || { echo "FAIL: no verilator found (set VERILATOR=...)"; exit 1; }
mkdir -p "$OUT"
RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f")
"$VL" --binary --timing -j 16 -Wno-fatal -Wno-lint -Wno-style \
    -I"$SRC/rtl/nonlin" -I"$SRC/rtl/seq" -I"$SRC/tb/chip" --top-module tb_mb_demo \
    -Mdir "$OUT/obj" -o "$OUT/tb_mb_demo" -CFLAGS -O2 \
    $RTL "$SRC/rtl/mem/gf180_sram_macro.v" "$SRC/demo/tb/tb_mb_demo.sv" >"$OUT/build.log" 2>&1 ||
    { echo "FAIL: verilator build (see $OUT/build.log)"; exit 1; }
echo "built $OUT/tb_mb_demo"
