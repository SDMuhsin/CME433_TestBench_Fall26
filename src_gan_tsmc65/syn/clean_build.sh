#!/usr/bin/env bash
# Drop the bulky, regenerable outputs of finished synthesis runs (server home quota):
#   src_gan_tsmc65/syn/clean_build.sh <syn_tag> ...      e.g. mb_park_14z_w16_ss_p2.4
# Removes build/syn/<tag>/{alib-52, *.spef, *.sdf}; keeps the netlist, ddc, sdc, reports and
# summaries. Rerun syn/run_syn.sh to regenerate them (PT, SDF GLS and power need them).
set -u
B=$(cd "$(dirname "$0")/.." && pwd)/build/syn
[ $# -ge 1 ] || { sed -n '2,5p' "$0"; exit 2; }
for t in "$@"; do
    d=$B/$t
    [ -d "$d" ] || { echo "skip $t (no $d)"; continue; }
    rm -rf "$d/alib-52"
    rm -f "$d"/*.spef "$d"/*.sdf
    echo "cleaned $t ($(du -sh "$d" | cut -f1) left)"
done
