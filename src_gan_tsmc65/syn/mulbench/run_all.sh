#!/usr/bin/env bash
# Bench flow of several designs, a few at a time (server):
#   syn/mulbench/run_all.sh <width> <jobs> <design> ...
# Log lines of every step go to stdout; summaries in build/summary/mb*_w<N>_*.txt.
set -u
M=$(cd "$(dirname "$0")" && pwd)
N=$1; J=$2; shift 2
printf '%s\n' "$@" | xargs -P "$J" -I{} "$M/run_design.sh" "$N" {}
echo "ALL_DONE w$N"
