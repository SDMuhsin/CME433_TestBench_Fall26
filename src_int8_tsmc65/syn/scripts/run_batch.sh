#!/usr/bin/env bash
# Sequential batch of DC runs on the server:  syn/scripts/run_batch.sh <corner>:<period> ...
#   e.g. run_batch.sh ss:5 ss:4 tt:5     (topographical mode; MQ65_TOPO=0 for wire-load)
# Prints one DC_DONE line per run, then BATCH_DONE. Results: build/syn/<corner>_p<period>/.
HERE=$(cd "$(dirname "$0")" && pwd)
for job in "$@"; do
    corner=${job%%:*}; period=${job#*:}
    echo "START $job $(date +%H:%M:%S)"
    "$HERE/run_dc.csh" "$period" "$corner" "${MQ65_TOPO:-1}"
    "$HERE/collect.sh" "$HERE/../../build/summary/syn_${corner}_p${period}.txt"
done
echo "BATCH_DONE $(date +%H:%M:%S)"
