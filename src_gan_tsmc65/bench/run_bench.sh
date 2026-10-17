#!/usr/bin/env bash
# End-to-end Fashion-MNIST benchmark of gan65_chip for one multiplier variant (docs/bench.md).
#   src_gan_tsmc65/bench/run_bench.sh [variant] [--n 256] [--jobs nproc-4] [--latch-rf]
#   variant  : exact (default) | <name> (bench/variants/<name>.v) | mq:<name> | path  (bench/variant.py)
#   --n      : number of latents from model/fmnist/latents.memh (max 256 as committed)
#   --jobs   : parallel chip simulations (each takes a contiguous slice of the latents)
#   --latch-rf: simulate the synthesised latch-RF memories instead of the fast flip-flop model
# Steps: Verilator build (cached), <jobs> pad-level chip simulations, scoring against the golden
# integer model + classifier.  Outputs build/gan65/runs/<tag>_n<N>/, summary copied to
# src_gan_tsmc65/bench/results/<tag>_n<N>.md.  Exit 0 when the run completed (the numbers say
# whether the variant is exact).
set -u
T65=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$T65")
VAR=exact
[ $# -ge 1 ] && [ "${1#--}" = "$1" ] && { VAR=$1; shift; }
N=256; JOBS=$(( $(nproc) - 4 )); MEM=
while [ $# -gt 0 ]; do
    case "$1" in
        --n) N=$2; shift ;;
        --jobs) JOBS=$2; shift ;;
        --latch-rf) MEM=--latch-rf ;;
        *) echo "unknown option $1"; exit 2 ;;
    esac
    shift
done
[ "$VAR" != exact ] && [ -e "$VAR" ] && VAR=$(realpath "$VAR")
cd "$ROOT"
PY=${PYTHON:-python3}
TAG=$($PY -m src_gan_tsmc65.bench.variant --name "$VAR")${MEM:+_rf}
SIM=$ROOT/build/gan65/sim/$TAG
RUN=$ROOT/build/gan65/runs/${TAG}_n$N
MODEL=$T65/model/fmnist
"$T65/bench/build.sh" "$VAR" "$SIM" $MEM || exit 1
mkdir -p "$RUN/logs" "$RUN/prev"
# stale dumps of an earlier run must not reach the scorer
find "$RUN" -maxdepth 1 -name 'pix_*.memh' -exec mv -t "$RUN/prev" {} + 2>/dev/null
[ "$JOBS" -gt "$N" ] && JOBS=$N
T0=$(date +%s)
pids=()
for ((w = 0; w < JOBS; w++)); do
    FIRST=$(( w * N / JOBS )); COUNT=$(( (w + 1) * N / JOBS - FIRST ))
    "$SIM/gan65_bench_tb" +WDIR="$MODEL" +CSR_MEMH="$MODEL/csr.memh" +ZQ_ALL="$MODEL/latents.memh" \
        +FIRST=$FIRST +COUNT=$COUNT +OUT="$RUN/pix_$FIRST.memh" > "$RUN/logs/w$w.log" 2>&1 &
    pids+=($!)
done
echo "$JOBS simulations on $N latents -> $RUN"
rc=0
for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
T1=$(date +%s)
grep -L '^DONE' "$RUN"/logs/w*.log | grep -q . && rc=1
[ $rc -eq 0 ] || { echo "FAIL: a simulation failed (see $RUN/logs)"; exit 1; }
CLK=$(grep -h '^IMAGE' "$RUN"/logs/w*.log | awk '{s += $3} END {printf "%d", s / NR}')
echo "simulations: $((T1 - T0)) s wall, $CLK clk per image"
$PY -m src_gan_tsmc65.bench.score "$VAR" "$RUN" --n "$N" > "$RUN/score.log" 2>&1 ||
    { echo "FAIL: scoring (see $RUN/score.log)"; exit 1; }
printf '\nchip simulation: %s clk per image (START, stream at SCLK = clk/4, readback at clk/8); %s s wall on %s jobs\n' \
    "$CLK" "$((T1 - T0))" "$JOBS" >> "$RUN/results.md"
mkdir -p "$T65/bench/results"
cp "$RUN/results.md" "$T65/bench/results/${TAG}_n$N.md"
cat "$RUN/results.md"
