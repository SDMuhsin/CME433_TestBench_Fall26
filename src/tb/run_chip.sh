#!/usr/bin/env bash
# Chip-level test of mb_chip (pad-level QSPI host, multi-token prompt, bit-exact logits).
#   src/tb/run_chip.sh [build_dir] [-- --story "text" ...]   (default src/tb/build)
# Needs iverilog and a python3 with numpy (PYTHON=..., else /usr/bin/python3 is tried).
# Default vectors: two stories (31 tokens) with a state reset between them; ~15 s per token.
# Prints PASS/FAIL and the cycles per token; exit 0 only if the microcode RTL is up to date
# and every logit of every token matches src/golden bit for bit.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
BUILD=$SRC/tb/build
if [ $# -gt 0 ] && [ "$1" != "--" ]; then BUILD=$1; shift; fi
[ "${1:-}" = "--" ] && shift
mkdir -p "$BUILD/ucode"
cd "$ROOT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3

$PY -m src.ucode.gen_rom "$BUILD/ucode" &&
    diff -q "$BUILD/ucode/mb_ucode_rom.v" src/rtl/seq/mb_ucode_rom.v >/dev/null &&
    diff -q "$BUILD/ucode/mb_ucode_defs.vh" src/rtl/seq/mb_ucode_defs.vh >/dev/null ||
    { echo "FAIL ucode: RTL is stale, rerun python3 -m src.ucode.gen_rom"; exit 1; }

VEC=$BUILD/chip_vec
$PY -m src.golden.host.vectors src/golden/params/mamba_e96_fp16.npz "$VEC" "$@" || exit 1

RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f")
VVP=$BUILD/tb_mb_chip.vvp
iverilog -g2012 -Wall -I "$SRC/rtl/nonlin" -I "$SRC/rtl/seq" -I "$SRC/tb/chip" -s tb_mb_chip \
    -o "$VVP" $RTL "$SRC/rtl/mem/gf180_sram_macro.v" "$SRC/tb/chip/tb_mb_chip.sv" \
    2>"$BUILD/tb_mb_chip.compile.log" ||
    { echo "FAIL chip: compile error (see $BUILD/tb_mb_chip.compile.log)"; exit 1; }

LOG=$BUILD/tb_mb_chip.log
vvp -n "$VVP" "+VEC=$VEC" | tee "$LOG" | grep -E '^(TOKEN|  state|CYCLES|PASS|FAIL)'
grep -q '^PASS' "$LOG"
