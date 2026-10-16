#!/usr/bin/env bash
# Verilator build of the pipe-driven chip TB (demo/tb/tb_mq_demo.sv, full mq_chip RTL) with the
# INT8 multiplier int/mq_mul8.v replaced by a variant.
#   src_int8/bench/build.sh <variant> <out_dir>
#   <variant>: exact (rtl/int/mq_mul8.v) | <name> (bench/variants/<name>.v or bench/variants/<name>/*.v)
#              | a path to a .v file or a directory of .v files that defines module mq_mul8
# Produces <out_dir>/tb_mq_demo (same plusargs / pipe protocol as the demo build).
set -eu
SRC=$(cd "$(dirname "$0")/.." && pwd)
VAR=$1; mkdir -p "$2"; OUT=$(realpath "$2")
VL=${VERILATOR:-$(command -v verilator || ls -d /nix/store/*-verilator-5*/bin/verilator 2>/dev/null | head -1)}
[ -x "$VL" ] || { echo "FAIL: no verilator found (set VERILATOR=...)"; exit 1; }
if   [ "$VAR" = exact ];                  then MUL="$SRC/rtl/int/mq_mul8.v"
elif [ -f "$SRC/bench/variants/$VAR.v" ]; then MUL="$SRC/bench/variants/$VAR.v"
elif [ -d "$SRC/bench/variants/$VAR" ];   then MUL=$(ls "$SRC/bench/variants/$VAR"/*.v)
elif [ -f "$VAR" ];                       then MUL=$(realpath "$VAR")
elif [ -d "$VAR" ];                       then MUL=$(ls "$(realpath "$VAR")"/*.v)
else echo "FAIL: unknown variant $VAR"; exit 1; fi
mkdir -p "$OUT"
RTL=$(sed -e '/^\/\//d' -e '/^int\/mq_mul8\.v$/d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f")
echo "$MUL" > "$OUT/mul8_sources.txt"
"$VL" --binary --timing -j 16 -O3 -Wno-fatal -Wno-lint -Wno-style \
    -I"$SRC/rtl/nonlin" -I"$SRC/rtl/seq" -I"$SRC/tb/common" --top-module tb_mq_demo \
    -Mdir "$OUT/obj" -o "$OUT/tb_mq_demo" -CFLAGS "-O3 -march=native" \
    $RTL $MUL "$SRC/rtl/mem/gf180_sram_macro.v" "$SRC/demo/tb/tb_mq_demo.sv" >"$OUT/build.log" 2>&1 ||
    { echo "FAIL: verilator build (see $OUT/build.log)"; exit 1; }
echo "built $OUT/tb_mq_demo with $(echo $MUL | tr '\n' ' ')"
