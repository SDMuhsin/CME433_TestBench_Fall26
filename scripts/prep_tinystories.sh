#!/usr/bin/env bash
# Fetch TinyStories V2 (GPT-4) and build the byte-level corpus files used by the
# Mamba chips (src/, src_int8/) into data/tinystories/ (git-ignored).
#
#   scripts/prep_tinystories.sh          # validation split only (~22 MB; enough for tests/eval/demo)
#   scripts/prep_tinystories.sh --train  # also the training split (~2.2 GB text + ~2.2 GB .bin)
#
# Override the location with MAMBA_DATA_DIR. The INT8 golden tests read
# data/tinystories/val.bin (or $MAMBA_VAL_BIN).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${MAMBA_DATA_DIR:-$ROOT/data/tinystories}
URL=https://huggingface.co/datasets/roneneldan/TinyStories/resolve/main
mkdir -p "$OUT"
cd "$ROOT"

fetch() {  # <split>
  local txt="$OUT/TinyStoriesV2-GPT4-$1.txt"
  [ -s "$txt" ] || curl -L --fail -o "$txt" "$URL/TinyStoriesV2-GPT4-$1.txt"
}

fetch valid
[ -s "$OUT/val.bin" ] || python3 -m src.model.data "$OUT/TinyStoriesV2-GPT4-valid.txt" "$OUT/val.bin"

if [ "${1:-}" = "--train" ]; then
  fetch train
  [ -s "$OUT/train.bin" ] || python3 -m src.model.data "$OUT/TinyStoriesV2-GPT4-train.txt" "$OUT/train.bin"
fi
ls -l "$OUT"
