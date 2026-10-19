#!/usr/bin/env bash
# One-command power of a multiplier variant (on the server), from its phase-2 netlist:
#   src_gan_tsmc65/power/run_power.sh <variant> [--width 8|16] [--clock 2.0] [--corners "tt ss ff"]
#                                     [--syn-period 1.8] [--seed 0] [--sdf]
#   variant      exact | <name> | mq:<name> | path (bench/variant.py); the netlist
#                build/syn/<variant>_ss_p<syn-period> must exist (syn/run_syn.sh <variant>)
#   --clock      clock period in ns of the GLS / power run (default 2.0 = 500 MHz signoff)
#   --corners    PrimePower library corners (default tt)
#   --width      datapath width (default 8; 16 -> netlist build/syn/<variant>_w16_ss_p<syn-period>)
#   --seed       Fashion-MNIST reference latent <model>/ref_vectors/seed_<n>
#   --sdf        activity from an SDF-timed GLS (tt SDF; glitches counted) instead of zero delay
# Steps: gate-level simulation of one image with SAIF (reused if it exists at this clock),
# then PrimePower (averaged) per corner. Summaries: build/summary/pwr_*.txt.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] || { sed -n '2,13p' "$0"; exit 2; }
VAR=$1; shift
CLK=2.0; CORNERS=tt; SYNP=1.8; SEED=0; SDF=0; W=8
while [ $# -gt 0 ]; do
    case "$1" in
        --clock) CLK=$2; shift ;;
        --corners) CORNERS=$2; shift ;;
        --syn-period) SYNP=$2; shift ;;
        --seed) SEED=$2; shift ;;
        --sdf) SDF=1 ;;
        --width) W=$2; shift ;;
        *) echo "unknown option $1"; exit 2 ;;
    esac
    shift
done
VNAME=$(cd "$G/.." && python3 -m src_gan_tsmc65.bench.variant --name "$VAR" --width "$W") || exit 1
SYN=${VNAME}_ss_p$SYNP
[ -f "$G/build/syn/$SYN/gan65_chip.v" ] || { echo "no netlist build/syn/$SYN: run syn/run_syn.sh $VAR --period $SYNP"; exit 1; }
GLS=${SYN}_s$SEED
[ $SDF = 1 ] && { GLS=${GLS}_sdftt; export GAN65_GLS_SDF=tt; }
have=$("$G/sim/gls/saif_period.sh" "$G/build/gls/$GLS" 2>/dev/null)
if [ "$(awk -v a="$have" -v b="$CLK" 'BEGIN{print (a != "" && a + 0 == b + 0)}')" != 1 ]; then
    "$G/sim/gls/run_gls.csh" "$SYN" "$SEED" "$CLK" 1
fi
for c in $CORNERS; do
    "$G/power/run_power.csh" "$SYN" "$GLS" "$c"
    grep -E '^(total_power|leakage_power|  (chip|pe_array|mul8_all|latch_rf) +[0-9]|energy|image_time)' \
        "$G/build/summary/pwr_${SYN}_${GLS}_$c.txt"
done
