#!/usr/bin/env bash
# Sequential DC runs on the server:  syn/scripts/run_batch.sh <corner>:<period>[:<variant>] ...
#   e.g. run_batch.sh ss:3 ss:2.5 tt:2.5 ff:2.5        (variant default exact)
# Prints one DC_DONE line and the summary digest per run, then BATCH_DONE.
HERE=$(cd "$(dirname "$0")" && pwd)
G=$(dirname "$(dirname "$HERE")")
for job in "$@"; do
    IFS=: read -r corner period variant <<<"$job"
    variant=${variant:-exact}
    echo "START $job $(date +%H:%M:%S)"
    out=$("$HERE/run_dc.csh" "$period" "$corner" "$variant")
    echo "$out"
    "$HERE/digest.sh" "$G/build/summary/syn_$(echo "$out" | awk '{print $2}').txt"
done
echo "BATCH_DONE $(date +%H:%M:%S)"
