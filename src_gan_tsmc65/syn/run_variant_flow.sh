#!/usr/bin/env bash
# Full hardware flow of one multiplier variant for the docs/results.md s.5 table (on the server):
#   src_gan_tsmc65/syn/run_variant_flow.sh <variant> [--width 8|16] [--clean]
# 1. 400 MHz comparison point: DC 2.4 ns + Formality + PT ss/tt/ff at 2.5 ns, then SDF-timed
#    GLS of seed_0 + PrimePower tt at 2.5 ns;
# 2. delay columns: DC 1.8 ns + Formality + PT at 2.0 ns (min period, mul a->p delay).
# --width is passed to every step (16 = the INT16 chip of docs/width16.md, tags *_w16_*);
# --clean drops the bulky regenerable outputs afterwards (syn/clean_build.sh).
# Each step is the documented one-command script; summaries land in build/summary/.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] || { sed -n '2,9p' "$0"; exit 2; }
V=$1; shift
W=8; CLEAN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --width) W=$2; shift ;;
        --clean) CLEAN=1 ;;
        *) echo "unknown option $1"; exit 2 ;;
    esac
    shift
done
"$G/syn/run_syn.sh" "$V" --width "$W" --period 2.4 --signoff --sta-period 2.5 || exit 1
"$G/power/run_power.sh" "$V" --width "$W" --clock 2.5 --syn-period 2.4 --sdf || exit 1
"$G/syn/run_syn.sh" "$V" --width "$W" --period 1.8 --signoff --sta-period 2.0 || exit 1
if [ $CLEAN = 1 ]; then
    T=$(cd "$G/.." && python3 -m src_gan_tsmc65.bench.variant --name "$V" --width "$W")
    "$G/syn/clean_build.sh" "${T}_ss_p2.4" "${T}_ss_p1.8"
fi
echo "FLOW_DONE $V"
