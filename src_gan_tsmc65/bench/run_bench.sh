#!/usr/bin/env bash
# End-to-end Fashion-MNIST benchmark of gan65_chip for one multiplier variant (docs/bench.md).
#   src_gan_tsmc65/bench/run_bench.sh [variant] [--width 8|16] [--n 256] [--from A] [--to B] [--jobs nproc-4] [--latch-rf]
#   variant  : exact (default) | <name> (bench/variants/<name>.v) | mq:<name> | mb:<design> | path
#              (bench/variant.py)
#   --width  : datapath width (default 8; 16 = the INT16 chip of docs/width16.md, model/fmnist_w16,
#              output tags <variant>_w16)
#   --n      : number of latents: <model>/latents.memh (256 committed); N > 256 generates
#              build/gan65/latents/latents[_w16]_n<N>.memh with the same seed (first 256 identical)
#   --from/--to: simulate only latents A..B-1 of N (default 0..N), to split a long run into chunks;
#              --from 0 clears earlier dumps, scoring runs once the chunk ending at N is done
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
N=256; JOBS=$(( $(nproc) - 4 )); MEM=; FROM=0; TO=; W=8
while [ $# -gt 0 ]; do
    case "$1" in
        --n) N=$2; shift ;;
        --jobs) JOBS=$2; shift ;;
        --from) FROM=$2; shift ;;
        --to) TO=$2; shift ;;
        --latch-rf) MEM=--latch-rf ;;
        --width) W=$2; shift ;;
        *) echo "unknown option $1"; exit 2 ;;
    esac
    shift
done
TO=${TO:-$N}
[ "$FROM" -lt "$TO" ] && [ "$TO" -le "$N" ] || { echo "bad range $FROM..$TO of $N"; exit 2; }
[ "$VAR" != exact ] && [ -e "$VAR" ] && VAR=$(realpath "$VAR")
cd "$ROOT"
PY=${PYTHON:-python3}
TAG=$($PY -m src_gan_tsmc65.bench.variant --name "$VAR" --width "$W")${MEM:+_rf}
SIM=$ROOT/build/gan65/sim/$TAG
RUN=$ROOT/build/gan65/runs/${TAG}_n$N
MODEL=$($PY -m src_gan_tsmc65.common.paths --model-dir "$W") || exit 1
ZQ=$MODEL/latents.memh
if [ "$N" -gt 256 ]; then
    ZQ=$ROOT/build/gan65/latents/latents$([ "$W" = 8 ] || echo "_w$W")_n$N.memh
    [ -s "$ZQ" ] || { mkdir -p "$(dirname "$ZQ")" && $PY -m src_gan_tsmc65.golden.latents --width "$W" --n "$N" --out "$ZQ"; } || exit 1
fi
"$T65/bench/build.sh" "$VAR" "$SIM" $MEM --width "$W" || exit 1
mkdir -p "$RUN/logs" "$RUN/prev"
# stale dumps and logs of an earlier run must not reach the scorer
[ "$FROM" -eq 0 ] && find "$RUN" "$RUN/logs" -maxdepth 1 \( -name 'pix_*.memh' -o -name 'w*.log' -o -name 'wall_*' \) \
    -exec mv --backup=numbered -t "$RUN/prev" {} + 2>/dev/null
M=$(( TO - FROM ))
[ "$JOBS" -gt "$M" ] && JOBS=$M
T0=$(date +%s)
pids=(); logs=()
for ((w = 0; w < JOBS; w++)); do
    FIRST=$(( FROM + w * M / JOBS )); COUNT=$(( FROM + (w + 1) * M / JOBS - FIRST ))
    "$SIM/gan65_bench_tb" +WDIR="$MODEL" +CSR_MEMH="$MODEL/csr.memh" +ZQ_ALL="$ZQ" \
        +FIRST=$FIRST +COUNT=$COUNT +OUT="$RUN/pix_$FIRST.memh" > "$RUN/logs/w$FIRST.log" 2>&1 &
    logs+=("$RUN/logs/w$FIRST.log")
    pids+=($!)
done
echo "$JOBS simulations on latents $FROM..$((TO - 1)) of $N -> $RUN"
rc=0
for pid in "${pids[@]}"; do wait "$pid" || rc=1; done
T1=$(date +%s)
grep -L '^DONE' "${logs[@]}" | grep -q . && rc=1
[ $rc -eq 0 ] || { echo "FAIL: a simulation failed (see $RUN/logs)"; exit 1; }
echo $((T1 - T0)) > "$RUN/wall_$FROM"
[ "$TO" -eq "$N" ] || { echo "simulations: $((T1 - T0)) s wall for latents $FROM..$((TO - 1)); score after the last chunk"; exit 0; }
WALL=$(cat "$RUN"/wall_* | awk '{s += $1} END {print s}')
CLK=$(grep -h '^IMAGE' "$RUN"/logs/w*.log | awk '{s += $3} END {printf "%d", s / NR}')
echo "simulations: $WALL s wall, $CLK clk per image"
$PY -m src_gan_tsmc65.bench.score "$VAR" "$RUN" --width "$W" --n "$N" --zq "$ZQ" > "$RUN/score.log" 2>&1 ||
    { echo "FAIL: scoring (see $RUN/score.log)"; exit 1; }
printf '\nchip simulation: %s clk per image (START, stream at SCLK = clk/4, readback at clk/8); %s s wall on %s jobs\n' \
    "$CLK" "$WALL" "$JOBS" >> "$RUN/results.md"
mkdir -p "$T65/bench/results"
cp "$RUN/results.md" "$T65/bench/results/${TAG}_n$N.md"
cat "$RUN/results.md"
