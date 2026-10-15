#!/usr/bin/env bash
# Sequential PrimeTime runs:  sta/run_batch.sh <syn_tag>:<corner>[:<rc>] ...
#   e.g. run_batch.sh ss_p4:ss tt_p4:tt ff_p4:ff:min ss_p4:ff:min
# Prints one PT_DONE line and the summary's timing lines per run, then BATCH_DONE.
HERE=$(cd "$(dirname "$0")" && pwd)
for job in "$@"; do
    IFS=: read -r tag corner rc <<<"$job"
    rc=${rc:-max}
    echo "START $job $(date +%H:%M:%S)"
    "$HERE/run_pt.csh" "$tag" "$corner" "$rc"
    grep -E '^(setup|hold|latch)' "$HERE/../build/summary/sta_${tag}_${corner}_${rc}.txt"
done
echo "BATCH_DONE $(date +%H:%M:%S)"
