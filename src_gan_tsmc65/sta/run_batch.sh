#!/usr/bin/env bash
# Sequential PrimeTime runs:  sta/run_batch.sh <syn_tag>:<corner>[:<rc>[:<period>]] ...
#   e.g. run_batch.sh exact_ss_p2.5:ss exact_ss_p2.5:tt exact_ss_p2.5:ff:min
# Prints one PT_DONE line and the summary's timing lines per run, then BATCH_DONE.
HERE=$(cd "$(dirname "$0")" && pwd)
for job in "$@"; do
    IFS=: read -r tag corner rc period <<<"$job"
    rc=${rc:-max}
    echo "START $job $(date +%H:%M:%S)"
    out=$("$HERE/run_pt.csh" "$tag" "$corner" "$rc" $period)
    echo "$out"
    grep -E '^(setup|hold|latch)' "$HERE/../build/summary/$(echo "$out" | awk '{print $2}').txt"
done
echo "BATCH_DONE $(date +%H:%M:%S)"
