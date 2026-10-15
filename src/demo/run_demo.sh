#!/usr/bin/env bash
# Closed-loop demo: the 3 demo stories generated on the RTL chip (iverilog), in parallel.
#   src/demo/run_demo.sh [--max-bytes N] [--prompt "text" ...]   (from anywhere)
# Build/run products go to src/demo/build (git-ignored); one <story>.json + logs per prompt.
# ~15 s of simulation per token, so a 200-byte story takes ~50 min. Exit 0 only if every
# story's every token is bit-exact and the text equals the golden-only generation.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
BUILD=$SRC/demo/build
cd "$ROOT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3

MAXB=()
PROMPTS=()
while [ $# -gt 0 ]; do
    case $1 in
        --max-bytes) MAXB=(--max-bytes "$2"); shift 2 ;;
        --prompt) PROMPTS+=("$2"); shift 2 ;;
        *) echo "unknown argument $1"; exit 2 ;;
    esac
done
[ ${#PROMPTS[@]} -gt 0 ] || PROMPTS=("Once upon a time" "Lily wanted" "The little dog")

mkdir -p "$BUILD"
RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f")
VVP=$BUILD/tb_mb_demo.vvp
iverilog -g2012 -Wall -I "$SRC/rtl/nonlin" -I "$SRC/rtl/seq" -I "$SRC/tb/chip" -s tb_mb_demo \
    -o "$VVP" $RTL "$SRC/rtl/mem/gf180_sram_macro.v" "$SRC/demo/tb/tb_mb_demo.sv" \
    2>"$BUILD/tb_mb_demo.compile.log" ||
    { echo "FAIL: compile error (see $BUILD/tb_mb_demo.compile.log)"; exit 1; }

pids=()
for p in "${PROMPTS[@]}"; do
    $PY -m src.demo.host.closed_loop "$VVP" "$BUILD" --prompt "$p" "${MAXB[@]}" &
    pids+=($!)
done
rc=0
for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
exit $rc
