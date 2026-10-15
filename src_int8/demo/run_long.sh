#!/usr/bin/env bash
# Long-context RTL check: Verilator build of the full chip, then >1k tokens without reset.
#   src_int8/demo/run_long.sh <val.bin> [--full]
# Runs in parallel: forced input val.bin[5000379:+2048] (stories joined by EOS, boundaries
# crossed) and closed loop (1200 sampled tokens, through EOS); --full adds the 8192-token forced
# run val.bin[12000432:+8192].  ~0.3 s per token per run.
# Outputs: src_int8/demo/build/long_{forced,closed,forced_8k}/long.json + host.log;
# exit 0 only if every run PASSes.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
[ $# -ge 1 ] || { echo "usage: $0 <val.bin> [--full]"; exit 2; }
VAL=$(realpath "$1"); shift
FULL=0; [ "${1:-}" = "--full" ] && FULL=1
cd "$ROOT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3
"$SRC/demo/tb/build_verilator.sh" || exit 1
SIM=$SRC/demo/build/verilator/tb_mq_demo
pids=()
$PY -m src_int8.demo.host.long_run "$SIM" "$SRC/demo/build/long_forced" --tokens 2048 --text-bin "$VAL" --offset 5000379 &
pids+=($!)
$PY -m src_int8.demo.host.long_run "$SIM" "$SRC/demo/build/long_closed" --tokens 1200 &
pids+=($!)
if [ $FULL -eq 1 ]; then
    $PY -m src_int8.demo.host.long_run "$SIM" "$SRC/demo/build/long_forced_8k" --tokens 8192 --text-bin "$VAL" --offset 12000432 &
    pids+=($!)
fi
rc=0
for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
exit $rc
