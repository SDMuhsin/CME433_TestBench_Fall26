#!/usr/bin/env bash
# One line per DC summary file: tag, area, cells, setup/hold WNS and TNS.
#   syn/scripts/collect.sh build/summary/syn_*.txt
for f in "$@"; do
    [ -f "$f" ] || { echo "$(basename "$f" .txt) MISSING"; continue; }
    awk -v t="$(basename "$f" .txt)" '
        /^total_cell_area_um2/ {a=$2} /^leaf_cells/ {n=$2}
        /^setup / {sw=$3; st=$6} /^setup_to_flops/ {fw=$3} /^hold/ {hw=$3; ht=$6}
        END {printf "%-12s area %s um2  cells %s  setup WNS %s TNS %s  hold WNS %s TNS %s  flop-path WNS %s\n", t, a, n, sw, st, hw, ht, fw}' "$f"
done
