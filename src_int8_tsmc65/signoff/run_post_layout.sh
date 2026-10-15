#!/usr/bin/env bash
# Post-layout sign-off of a routed block, step by step:
#   signoff/run_post_layout.sh <pnr_tag> [step ...]
# steps (default: all, in this order):
#   star   StarRC extraction (typical RC)          ext/run_star.csh
#   lec    Formality, DC netlist vs routed netlist  lec/run_fm.csh <tag> post
#   sta    PrimeTime ss / tt / ff                  sta/post/run_pt_post.csh
#   fmax   PrimeTime period sweep at ss            sta/post/run_pt_post.csh (pt_fmax)
#   gls    zero-delay GLS of the routed netlist: 31 tokens at 4 ns, 2 tokens at 40 ns
#   power  PrimeTime PX at tt, 250 MHz and 25 MHz   power/post/run_power_post.csh
#   drc    Calibre DRC (main and antenna decks)    signoff/drc/run_drc.csh
#   lvs    Calibre LVS                             signoff/lvs/run_lvs.csh
# Corner / RC pairs for STA: ss and ff use the ICC2 extraction with the worst / best RC
# model (the kit's StarRC model is typical only); tt uses StarRC. ss and ff are also run
# on the StarRC typical SPEF, labelled as such.
set -u
T=$1; shift
M=$(cd "$(dirname "$0")/.." && pwd)
steps=${*:-star lec sta fmax gls power drc lvs}
for s in $steps; do
    echo "STEP $s $(date +%H:%M:%S)"
    case $s in
    star)  "$M/ext/run_star.csh" "$T" ;;
    lec)   "$M/lec/run_fm.csh" "$T" post ;;
    sta)   for j in ss:icc2_ss tt:star ff:icc2_ff tt:icc2_tt ss:star ff:star; do
               "$M/sta/post/run_pt_post.csh" "$T" "${j%%:*}" "${j#*:}"
           done ;;
    fmax)  MQ65_PERIODS="${MQ65_PERIODS:-4.0 3.8 3.6 3.4 3.2 3.0 2.9 2.8 2.7 2.6}" MQ65_PT_SCRIPT=pt_fmax \
               "$M/sta/post/run_pt_post.csh" "$T" ss icc2_ss ;;
    gls)   MQ65_GLS_PNR=1 "$M/sim/gls/run_gls.csh" "$T" tok31
           MQ65_GLS_PNR=1 "$M/sim/gls/run_gls.csh" "$T" tok2 1ns ;;
    power) "$M/power/post/run_power_post.csh" "$T" "post_${T}_tok31" tt star 4
           "$M/power/post/run_power_post.csh" "$T" "post_${T}_tok2" tt star 40 ;;
    drc)   "$M/signoff/drc/run_drc.csh" "$T" MQ65_DRC_DECK
           "$M/signoff/drc/run_drc.csh" "$T" MQ65_ANT_DECK ;;
    lvs)   "$M/signoff/lvs/run_lvs.csh" "$T" ;;
    *)     echo "unknown step $s" ;;
    esac
done
echo "POST_DONE $T $(date +%H:%M:%S)"
