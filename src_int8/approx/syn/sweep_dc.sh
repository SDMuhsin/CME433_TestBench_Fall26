#!/usr/bin/env bash
# Area-delay sweep of one variant (sequential DC runs):
#   src_int8/approx/syn/sweep_dc.sh <variant> <corner> "<delays_ns>" [NAME=VALUE ...]
# e.g. sweep_dc.sh cssm tt "0.6 0.8 1.0 1.5 2.0 3.0" CSSM_M=6
D=$(cd "$(dirname "$0")" && pwd)
v=$1; c=$2; delays=$3; shift 3
for d in $delays; do "$D/run_dc.csh" "$v" "$c" "$d" "$@"; done
