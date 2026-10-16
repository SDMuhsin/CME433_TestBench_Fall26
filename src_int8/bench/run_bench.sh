#!/usr/bin/env bash
# RTL-run byte-LM benchmark of mq_chip for one INT8 multiplier variant (docs/bench.md).
#   src_int8/bench/run_bench.sh <variant> [--n 512] [--length 1024] [--jobs nproc-4] [--val val.bin]
#   <variant>: see bench/build.sh (exact = rtl/int/mq_mul8.v)
# Steps: crops + tables (once), Python golden reference (once), Verilator build of the chip with the
# variant, <jobs> parallel chip simulations over disjoint crop subsets (state reset per crop),
# alongside them the Python emulator of the variant (bench/emu, non-exact variants), scoring. Outputs build/bench/runs/<variant>_c<n>x<length>/results.{md,json}, copied to
# src_int8/bench/results/<variant>_c<n>x<length>.{md,json}. An interrupted run resumes.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
[ $# -ge 1 ] || { echo "usage: $0 <variant> [--n N] [--length L] [--jobs J] [--val val.bin]"; exit 2; }
VAR=$1; shift
[ "$VAR" != exact ] && [ -e "$VAR" ] && VAR=$(realpath "$VAR")
N=512; LEN=1024; JOBS=$(( $(nproc) - 4 )); VAL=$ROOT/data/tinystories/val.bin
while [ $# -gt 0 ]; do
    case "$1" in
        --n) N=$2; shift ;;
        --length) LEN=$2; shift ;;
        --jobs) JOBS=$2; shift ;;
        --val) VAL=$(realpath "$2"); shift ;;
        *) echo "unknown option $1"; exit 2 ;;
    esac
    shift
done
cd "$ROOT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3
NAME=$(basename "${VAR%.v}")
BENCH=$ROOT/build/bench/c${N}x${LEN}
RUN=$ROOT/build/bench/runs/${NAME}_c${N}x${LEN}
SIM=$ROOT/build/bench/sim/$NAME
mkdir -p "$RUN/workers"
[ -f "$BENCH/crops.npy" ] || $PY -m src_int8.bench.prep "$VAL" "$BENCH" --n "$N" --length "$LEN" || exit 1
REF_PID=
[ -f "$BENCH/ref/nll.npy" ] || { $PY -m src_int8.bench.ref "$BENCH" > "$RUN/ref.log" 2>&1 & REF_PID=$!; }
"$SRC/bench/build.sh" "$VAR" "$SIM" || exit 1

EMU_PID=
if [ "$NAME" != exact ]; then      # Python reference for this variant (golden + its mul8 table)
    $PY -m src_int8.bench.emu.run "$VAR" "$BENCH" > "$RUN/emu.log" 2>&1 & EMU_PID=$!
fi
T0=$(date +%s)
pids=()
for ((w = 0; w < JOBS; w++)); do
    $PY -m src_int8.bench.worker "$SIM/tb_mq_demo" "$BENCH" "$RUN" --worker $w --jobs "$JOBS" \
        > "$RUN/workers/w$w.log" 2>&1 &
    pids+=($!)
done
echo "$JOBS workers on $N crops x $LEN bytes -> $RUN"
rc=0
for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
T1=$(date +%s)
[ -z "$REF_PID" ] || wait "$REF_PID" || rc=1
[ -z "$EMU_PID" ] || wait "$EMU_PID" || rc=1
[ $rc -eq 0 ] || { echo "FAIL: a worker or a Python reference failed (see $RUN/workers, $RUN/{ref,emu}.log)"; exit 1; }
echo "{\"wall_s\": $((T1 - T0)), \"jobs\": $JOBS}" > "$RUN/wall.json"

BASE=$ROOT/build/bench/runs/exact_c${N}x${LEN}
BARG=(); [ "$NAME" != exact ] && [ -f "$BASE/nll.npy" ] && BARG=(--baseline "$BASE")
$PY -m src_int8.bench.score "$BENCH" "$RUN" --variant "$NAME" "${BARG[@]}" || exit 1
mkdir -p "$SRC/bench/results"
cp "$RUN/results.md" "$SRC/bench/results/${NAME}_c${N}x${LEN}.md"
cp "$RUN/results.json" "$SRC/bench/results/${NAME}_c${N}x${LEN}.json"
