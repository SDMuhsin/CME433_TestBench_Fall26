#!/usr/bin/env bash
# Data link for the standalone multiplier runs (host / clone from src_int8_tsmc65/site/site.sh).
# Code reaches the server through git; only vectors go up and summary text comes down.
#   src_int8/approx/syn/sync.sh vec    build/approx/act/vec_*.hex -> server clone build/approx/act/
#   src_int8/approx/syn/sync.sh pull   server build/approx/summary/ -> build/approx/summary/
set -eu
APX=$(cd "$(dirname "$0")/.." && pwd); ROOT=$(dirname "$(dirname "$APX")")
. "$ROOT/src_int8_tsmc65/site/site.sh"
R="$MQ65_HOST:$(dirname "$MQ65_REMOTE")/build/approx"
case "${1:-}" in
vec)  ssh -n -o BatchMode=yes "$MQ65_HOST" "mkdir -p $(dirname "$MQ65_REMOTE")/build/approx/act"
      rsync -rltp -e ssh "$ROOT"/build/approx/act/vec_*.hex "$R/act/" ;;
pull) mkdir -p "$ROOT/build/approx/summary"
      rsync -rltp -e ssh "$R/summary/" "$ROOT/build/approx/summary/" ;;
*)    echo "usage: $0 vec|pull"; exit 1 ;;
esac
