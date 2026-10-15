#!/usr/bin/env bash
# Verilator build of the chip TB (tb_mq_chip.sv + the full mq_chip RTL, chip.f), the fast
# replacement for the iverilog image used by run_chip.sh --vl (about 1 s per token vs ~15 s).
#   src_int8/tb/build_verilator.sh [out_dir]   (default src_int8/tb/build/verilator)
# Verilator: $VERILATOR, else `verilator` on PATH (source src_int8/flow/env.sh for the nix one),
# else the first Verilator 5 in /nix/store.
set -eu
SRC=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$SRC/tb/build/verilator}
VL=${VERILATOR:-$(command -v verilator || ls -d /nix/store/*-verilator-5*/bin/verilator 2>/dev/null | head -1)}
[ -x "$VL" ] || { echo "FAIL: no verilator found (set VERILATOR=...)"; exit 1; }
mkdir -p "$OUT"
RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f")
"$VL" --binary --timing -j 16 -Wno-fatal -Wno-lint -Wno-style \
    -I"$SRC/rtl/nonlin" -I"$SRC/rtl/seq" -I"$SRC/tb/common" --top-module tb_mq_chip \
    -Mdir "$OUT/obj" -o "$OUT/tb_mq_chip" -CFLAGS -O2 \
    $RTL "$SRC/rtl/mem/gf180_sram_macro.v" "$SRC/tb/chip/tb_mq_chip.sv" >"$OUT/build.log" 2>&1 ||
    { echo "FAIL: verilator build (see $OUT/build.log)"; exit 1; }
echo "built $OUT/tb_mq_chip"
