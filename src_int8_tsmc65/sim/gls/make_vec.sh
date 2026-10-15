#!/usr/bin/env bash
# Cut the chip-TB golden vectors down to the first N tokens for gate-level simulation.
#   sim/gls/make_vec.sh <vec_dir> <ntok> <out_dir>
#   vec_dir: output of `python -m src_int8.golden.vectors <dir> --chip-only` (<dir>/chip)
# Then `sync.sh vec <out_dir>` copies them to the server ($MQ65/build/gls/vec/<name>).
set -eu
SRC=$1; N=$2; OUT=$3
mkdir -p "$OUT"
head -n "$N" "$SRC/plan.memh" > "$OUT/plan.memh"
head -n $((N * 54280)) "$SRC/stream.memh" > "$OUT/stream.memh"
head -n $((N * 128)) "$SRC/logits.memh" > "$OUT/logits.memh"
head -n $((N * 0x1200)) "$SRC/host.memh" > "$OUT/host.memh"
wc -l "$OUT"/*.memh | tail -n 1
