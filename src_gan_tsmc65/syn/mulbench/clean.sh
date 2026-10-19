#!/usr/bin/env bash
# Remove the regenerable bulk of the bench runs (server): Milkyway libs, WORK dirs, SPEF, SDF,
# SAIF, GLS outputs. Summaries (build/summary/mb*) and netlists stay.
#   syn/mulbench/clean.sh
G=$(cd "$(dirname "$0")/../.." && pwd)
B=$G/build/mulbench
[ -d "$B" ] || exit 0
rm -rf "$B"/*/mb_mw "$B"/*/work "$B"/*/*.spef "$B"/*/*.sdf "$B"/*/*/mul_bench.saif "$B"/*/*/simv* \
    "$B"/*/*/csrc "$B"/*/*/stim.memh "$B"/*/alib-* "$B"/*/fm/FM_WORK* "$B"/*/fm/formality*_svf
du -sh "$B"
