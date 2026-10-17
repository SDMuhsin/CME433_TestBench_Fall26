#!/usr/bin/env bash
# One-screen digest of DC summary files: area split, timing (setup / hold / through the multiplier).
#   syn/scripts/digest.sh build/summary/syn_<tag>.txt ...
for f in "$@"; do
    [ -f "$f" ] || { echo "$(basename "$f" .txt) MISSING"; continue; }
    echo "== $(basename "$f" .txt)"
    grep -E '^(total_cell_area|leaf_cells)' "$f"
    sed -n '/^area_split/,/^pe_instances/p' "$f"
    grep -E '^(setup|hold)' "$f"
done
