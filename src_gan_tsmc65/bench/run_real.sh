#!/usr/bin/env bash
# Real-data (GAN-paper) scoring of gan65_chip images against Fashion-MNIST (docs/bench.md).
#   src_gan_tsmc65/bench/run_real.sh [--n 10000] [--width 8|16] [--chunk 3400] [--skip-rtl] [--device cuda:1] [variant ...]
# 1. For every variant (default: the seven of docs/bench.md) runs bench/run_bench.sh --n N, so all
#    images come from the Verilator RTL runs (build/gan65/runs/<tag>_n<N>/rtl_u8.npy), one variant
#    at a time in chunks of --chunk latents (each chunk < 30 min on 44 jobs; the EvoApprox netlists
#    simulate ~5x slower than the behavioural multipliers). --skip-rtl reuses existing runs.
# 2. Scores the RTL images and the reference rows (real test set, float generator, int8 golden)
#    with bench/real (FID / IS / KID / precision-recall vs the 60k train set, plus domain metrics).
#    --width 16: the 16-bit chip (default variant exact), its INT16 golden row; the table keeps the
#    cached 8-bit rows too.
#    Output: build/gan65/real/real_n<N>.{json,md} (per-row cache build/gan65/real/n<N>/),
#    copied to src_gan_tsmc65/bench/results/real_n<N>.md.
set -u -o pipefail
T65=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$T65")
N=10000; CHUNK=3400; RTL=1; DEV=cuda:1; VARS=(); W=8
while [ $# -gt 0 ]; do
    case "$1" in
        --n) N=$2; shift ;;
        --chunk) CHUNK=$2; shift ;;
        --skip-rtl) RTL=0 ;;
        --device) DEV=$2; shift ;;
        --width) W=$2; shift ;;
        *) VARS+=("$1") ;;
    esac
    shift
done
if [ ${#VARS[@]} -eq 0 ]; then
    VARS=(exact)
    [ "$W" = 8 ] && VARS=(exact mq:evo_1KV8 mq:ilm example_trunc4 mq:evo_1KR8 mq:evo_1KVL mq:evo_1KR3)
fi
if [ $RTL -eq 1 ]; then
    for v in "${VARS[@]}"; do
        for ((a = 0; a < N; a += CHUNK)); do
            b=$(( a + CHUNK < N ? a + CHUNK : N ))
            "$T65/bench/run_bench.sh" "$v" --width "$W" --n "$N" --from $a --to $b | tail -2 || exit 1
        done
    done
fi
cd "$ROOT"
# one invocation per row (each a few minutes on one GPU); rows already scored are cached
for r in real float golden "${VARS[@]}"; do
    python3 -m src_gan_tsmc65.bench.real.run --n "$N" --width "$W" --device "$DEV" "$r" | tail -1 || exit 1
done
mkdir -p "$T65/bench/results"
cp "build/gan65/real/real_n$N.md" "$T65/bench/results/real_n$N.md"
