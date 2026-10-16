#!/usr/bin/env bash
# Area-delay sweep of every design in variants.txt (or a given list file), one after another:
#   src_int8/approx/syn/sweep_all.sh <corner> "<delays_ns>" [list_file]
D=$(cd "$(dirname "$0")" && pwd)
c=$1; delays=$2; list=${3:-$D/variants.txt}
grep -v '^#' "$list" | while read -r v defs; do
    [ -n "$v" ] && "$D/sweep_dc.sh" "$v" "$c" "$delays" $defs
done
