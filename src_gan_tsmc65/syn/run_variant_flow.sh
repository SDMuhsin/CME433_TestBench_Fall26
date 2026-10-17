#!/usr/bin/env bash
# Full hardware flow of one multiplier variant for the docs/results.md s.5 table (on the server):
#   src_gan_tsmc65/syn/run_variant_flow.sh <variant>
# 1. 400 MHz comparison point: DC 2.4 ns + Formality + PT ss/tt/ff at 2.5 ns, then SDF-timed
#    GLS of seed_0 + PrimePower tt at 2.5 ns;
# 2. delay columns: DC 1.8 ns + Formality + PT at 2.0 ns (min period, mul8 a->p delay).
# Each step is the documented one-command script; summaries land in build/summary/.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
[ $# -eq 1 ] || { sed -n '2,7p' "$0"; exit 2; }
V=$1
"$G/syn/run_syn.sh" "$V" --period 2.4 --signoff --sta-period 2.5 || exit 1
"$G/power/run_power.sh" "$V" --clock 2.5 --syn-period 2.4 --sdf || exit 1
"$G/syn/run_syn.sh" "$V" --period 1.8 --signoff --sta-period 2.0 || exit 1
echo "FLOW_DONE $V"
