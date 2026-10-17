#!/usr/bin/env bash
# Clock period (ns) a GLS SAIF was recorded at:  sim/gls/saif_period.sh <gls_dir>
#   = SAIF DURATION / the window's clock count from tb.log ("SAIF window closed ... <n> clk")
d=$1
dur=$(grep -m1 -oE '\(DURATION [0-9.eE+]+\)' "$d/gan65_chip.saif" | grep -oE '[0-9.eE+]+')
ts=$(grep -m1 -oE '\(TIMESCALE [0-9]+ ?[a-z]+\)' "$d/gan65_chip.saif" | sed -E 's/\(TIMESCALE ([0-9]+) ?([a-z]+)\)/\1 \2/')
n=$(grep -m1 -oE 'SAIF window closed at [0-9]+, [0-9]+ clk' "$d/tb.log" | awk '{print $6}')
[ -n "$dur" ] && [ -n "$n" ] || { echo "saif_period: no SAIF window in $d" >&2; exit 1; }
echo "$dur $ts $n" | awk '{s = ($3 == "ps") ? 1e-3 : ($3 == "fs") ? 1e-6 : 1; printf "%g\n", $1 * $2 * s / $4}'
