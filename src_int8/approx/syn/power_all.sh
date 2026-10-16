#!/usr/bin/env bash
# Gate-level power of every design in variants.txt (or a given list file) at one DC point:
#   src_int8/approx/syn/power_all.sh <corner> <max_delay_ns> "<vecs>" [period_ns=4] [list_file]
# e.g. power_all.sh tt 4.0 "chip random" 4   (netlists from sweep_all.sh / run_dc.csh)
D=$(cd "$(dirname "$0")" && pwd)
c=$1; d=$2; vecs=$3; per=${4:-4}; list=${5:-$D/variants.txt}
grep -v '^#' "$list" | while read -r v defs; do
    [ -n "$v" ] || continue
    tag=$v; for x in $defs; do tag=${tag}_${x//=/}; done
    for vec in $vecs; do "$D/run_power.csh" "${tag}_${c}_d$d" "$vec" "$per"; done
done
