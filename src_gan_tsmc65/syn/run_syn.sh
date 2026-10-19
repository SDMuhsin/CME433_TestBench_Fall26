#!/usr/bin/env bash
# One-command synthesis of gan65_chip with a multiplier variant (on the server):
#   src_gan_tsmc65/syn/run_syn.sh <variant> [--width 8|16] [--period 1.8] [--signoff [--sta-period 2.0]]
#   variant  : exact | <name> (bench/variants/<name>.v) | mq:<name> | mb:<design> | path  (bench/variant.py)
#   --width  : datapath width (default 8; 16 = docs/width16.md, tags <variant>_w16_<corner>_p<period>)
#   --period : DC clock period in ns (default 1.8 = the exact design's signoff netlist)
#   --signoff: also Formality (RTL vs netlist) and PrimeTime ss / tt setup + ff hold at
#              --sta-period (default 2.0 ns = 500 MHz, the signoff clock; docs/synthesis.md)
# DC runs at the ss corner (topographical). Results: build/syn/<variant>_ss_p<period>/,
# summaries in build/summary/ (syn_*, fm_*, sta_*); a digest is printed at the end.
set -u
G=$(cd "$(dirname "$0")/.." && pwd)
[ $# -ge 1 ] || { sed -n '2,10p' "$0"; exit 2; }
VAR=$1; shift
PERIOD=1.8; STA=2.0; SIGNOFF=0; export GAN65_WIDTH=8
while [ $# -gt 0 ]; do
    case "$1" in
        --period) PERIOD=$2; shift ;;
        --sta-period) STA=$2; shift ;;
        --signoff) SIGNOFF=1 ;;
        --width) GAN65_WIDTH=$2; shift ;;
        *) echo "unknown option $1"; exit 2 ;;
    esac
    shift
done
[ "$VAR" != exact ] && [ -e "$VAR" ] && VAR=$(realpath "$VAR")
out=$("$G/syn/scripts/run_dc.csh" "$PERIOD" ss "$VAR")
echo "$out"
TAG=$(echo "$out" | awk '{print $2}')
"$G/syn/scripts/digest.sh" "$G/build/summary/syn_$TAG.txt"
if [ $SIGNOFF = 1 ]; then
    "$G/lec/run_fm.csh" "$TAG"
    "$G/sta/run_batch.sh" "$TAG:ss:max:$STA" "$TAG:tt:max:$STA" "$TAG:ff:min:$STA" | grep -vE '^(START|BATCH_DONE)'
fi
