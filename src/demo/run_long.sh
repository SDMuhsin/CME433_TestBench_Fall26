#!/usr/bin/env bash
# Long-context RTL check: Verilator build of the full chip, then >1k tokens without reset.
#   src/demo/run_long.sh <val.bin> [tokens] [offset]   (defaults 2048, 5000379)
# Runs in parallel: forced input (val.bin bytes offset..offset+tokens-1, stories joined by EOS)
# and closed loop (1200 sampled tokens, through EOS). ~0.75 s per token per run.
# Outputs: src/demo/build/long_{forced,closed}/long.json + host.log; exit 0 only if both PASS.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
[ $# -ge 1 ] || { echo "usage: $0 <val.bin> [tokens] [offset]"; exit 2; }
VAL=$(realpath "$1"); TOK=${2:-2048}; OFF=${3:-5000379}
cd "$ROOT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3
"$SRC/demo/tb/build_verilator.sh" || exit 1
SIM=$SRC/demo/build/verilator/tb_mb_demo
$PY -m src.demo.host.long_run "$SIM" "$SRC/demo/build/long_forced" --tokens "$TOK" --text-bin "$VAL" --offset "$OFF" &
p1=$!
$PY -m src.demo.host.long_run "$SIM" "$SRC/demo/build/long_closed" --tokens 1200 &
p2=$!
rc=0
wait $p1 || rc=1
wait $p2 || rc=1
exit $rc
