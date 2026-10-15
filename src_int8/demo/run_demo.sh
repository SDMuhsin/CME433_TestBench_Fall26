#!/usr/bin/env bash
# Closed-loop demo: the demo stories generated on the RTL chip, in parallel (Verilator by default).
#   src_int8/demo/run_demo.sh [--iverilog] [--max-bytes N] [--prompt "text" ...]   (from anywhere)
# Default prompts: "Once upon a time", "Lily wanted", "The little dog", "The quick brown fox".
# Build/run products go to src_int8/demo/build (git-ignored); one <story>.json + logs per prompt.
# Verilator: ~0.3 s of simulation per token (a 200-byte story in ~1 min); iverilog ~15 s per
# token.  Exit 0 only if every story's every token is bit-exact and the text equals the
# golden-only generation.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
BUILD=$SRC/demo/build
cd "$ROOT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3

MAXB=()
PROMPTS=()
IVL=0
while [ $# -gt 0 ]; do
    case $1 in
        --iverilog) IVL=1; shift ;;
        --max-bytes) MAXB=(--max-bytes "$2"); shift 2 ;;
        --prompt) PROMPTS+=("$2"); shift 2 ;;
        *) echo "unknown argument $1"; exit 2 ;;
    esac
done
[ ${#PROMPTS[@]} -gt 0 ] || PROMPTS=("Once upon a time" "Lily wanted" "The little dog" "The quick brown fox")

mkdir -p "$BUILD"
if [ $IVL -eq 1 ]; then
    RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f")
    SIM=$BUILD/tb_mq_demo.vvp
    iverilog -g2012 -Wall -I "$SRC/rtl/nonlin" -I "$SRC/rtl/seq" -I "$SRC/tb/common" -s tb_mq_demo \
        -o "$SIM" $RTL "$SRC/rtl/mem/gf180_sram_macro.v" "$SRC/demo/tb/tb_mq_demo.sv" \
        2>"$BUILD/tb_mq_demo.compile.log" ||
        { echo "FAIL: compile error (see $BUILD/tb_mq_demo.compile.log)"; exit 1; }
else
    "$SRC/demo/tb/build_verilator.sh" || exit 1
    SIM=$BUILD/verilator/tb_mq_demo
fi

pids=()
for p in "${PROMPTS[@]}"; do
    $PY -m src_int8.demo.host.closed_loop "$SIM" "$BUILD" --prompt "$p" "${MAXB[@]}" &
    pids+=($!)
done
rc=0
for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
exit $rc
