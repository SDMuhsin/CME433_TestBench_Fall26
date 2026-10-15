#!/usr/bin/env bash
# Sequential Formality runs:  lec/run_batch.sh <syn_tag> ...     (e.g. ss_p4 tt_p4 ff_p4)
# Prints one FM_DONE line per run, then BATCH_DONE.
HERE=$(cd "$(dirname "$0")" && pwd)
for tag in "$@"; do
    echo "START $tag $(date +%H:%M:%S)"
    "$HERE/run_fm.csh" "$tag"
done
echo "BATCH_DONE $(date +%H:%M:%S)"
