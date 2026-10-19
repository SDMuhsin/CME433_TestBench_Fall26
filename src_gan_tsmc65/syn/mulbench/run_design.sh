#!/usr/bin/env bash
# Whole bench flow of one design (server):  syn/mulbench/run_design.sh <width> <design>
#   DC ss at 2.5 ns (400 MHz) + Formality + SDF GLS / PrimePower tt at 2.5 ns for the uniform and
#   GAN-like stimulus; DC ss at the relaxed 4.0 ns and at a tight period (1.0 ns at N = 8,
#   1.2 ns at N = 16: fastest netlist, its a -> p delay and min period = period - WNS).
set -u
M=$(cd "$(dirname "$0")" && pwd)
N=$1; D=$2
"$M/run_dc.csh" "$N" "$D" 2.5
"$M/run_fm.csh" "w${N}_${D}_p2.5"
"$M/run_power.csh" "w${N}_${D}_p2.5" uniform 2.5
"$M/run_power.csh" "w${N}_${D}_p2.5" gan 2.5
"$M/run_dc.csh" "$N" "$D" 4.0
"$M/run_dc.csh" "$N" "$D" "$([ "$N" = 8 ] && echo 1.0 || echo 1.2)"
echo "DESIGN_DONE w${N}_$D"
