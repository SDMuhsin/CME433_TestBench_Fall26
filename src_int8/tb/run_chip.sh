#!/usr/bin/env bash
# Chip-level test of mq_chip (pad-level QSPI host, multi-token prompt, bit-exact logits + state).
#   src_int8/tb/run_chip.sh [build_dir] [--ref] [--vl] [-- --story "text" ...]
#     build_dir  default src_int8/tb/build
#     --ref      vectors from the spec-formula reference (tb/ref, random params) instead of
#                src_int8/golden (trained params; default when golden/params exists)
#     --vl       run the Verilator image built by src_int8/tb/build_verilator.sh (fast) instead
#                of iverilog (~15 s per token)
# Prints PASS/FAIL and the cycles per token; exit 0 only if the microcode RTL is up to date and
# every logit / state byte of every token matches the vectors bit for bit.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
BUILD=$SRC/tb/build
USE_REF=0; USE_VL=0
while [ $# -gt 0 ] && [ "$1" != "--" ]; do
    case "$1" in
        --ref) USE_REF=1 ;;
        --vl)  USE_VL=1 ;;
        *)     BUILD=$1 ;;
    esac
    shift
done
[ "${1:-}" = "--" ] && shift
mkdir -p "$BUILD/ucode"
cd "$ROOT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3   # golden needs numpy; the nix python has none

$PY -m src_int8.ucode.gen_rom "$BUILD/ucode" &&
    diff -q "$BUILD/ucode/mq_ucode_rom.v" src_int8/rtl/seq/mq_ucode_rom.v >/dev/null &&
    diff -q "$BUILD/ucode/mq_ucode_defs.vh" src_int8/rtl/seq/mq_ucode_defs.vh >/dev/null ||
    { echo "FAIL ucode: RTL is stale, rerun python3 -m src_int8.ucode.gen_rom"; exit 1; }

if [ $USE_REF -eq 0 ] && [ -f src_int8/golden/params/mamba_e96_int8.npz ]; then
    VEC=$BUILD/vec/chip
    STORIES=(); for s in "$@"; do STORIES+=("$s"); done
    $PY -m src_int8.golden.vectors "$BUILD/vec" --chip-only "${STORIES[@]}" || exit 1
else
    VEC=$BUILD/vec_ref/chip
    $PY -m src_int8.tb.chip.gen_vectors "$VEC" "$@" || exit 1
fi

LOG=$BUILD/tb_mq_chip.log
if [ $USE_VL -eq 1 ]; then
    BIN=$BUILD/verilator/tb_mq_chip
    [ -x "$BIN" ] || { echo "FAIL chip: no $BIN (run src_int8/tb/build_verilator.sh)"; exit 1; }
    "$BIN" "+VEC=$VEC" | tee "$LOG" | grep -E '^(TOKEN|  state|CYCLES|PASS|FAIL)'
else
    RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f")
    VVP=$BUILD/tb_mq_chip.vvp
    iverilog -g2012 -Wall -I "$SRC/rtl/nonlin" -I "$SRC/rtl/seq" -I "$SRC/tb/common" -s tb_mq_chip \
        -o "$VVP" $RTL "$SRC/rtl/mem/gf180_sram_macro.v" "$SRC/tb/chip/tb_mq_chip.sv" \
        2>"$BUILD/tb_mq_chip.compile.log" ||
        { echo "FAIL chip: compile error (see $BUILD/tb_mq_chip.compile.log)"; exit 1; }
    vvp -n "$VVP" "+VEC=$VEC" | tee "$LOG" | grep -E '^(TOKEN|  state|CYCLES|PASS|FAIL)'
fi
grep -q '^PASS' "$LOG"
