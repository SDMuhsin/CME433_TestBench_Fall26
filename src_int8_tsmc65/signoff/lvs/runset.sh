#!/usr/bin/env bash
# Block-level LVS runset from the foundry deck (stdout):
#   runset.sh <deck> <gds> <source_netlist> <top> <power_net> <ground_net>
# Names are read case-sensitively: the deck leaves SOURCE CASE / LAYOUT CASE at the
# Calibre default (NO = fold case), which merges distinct synthesis nets such as n154 and
# N154 of the same module into one source net (151 such pairs in mq_chip). The two
# statements go next to LVS GROUND NAME (the end of the deck is a TVF block).
deck=$1; gds=$2; src=$3; top=$4; pwr=$5; gnd=$6
d=$(dirname "$deck")
sed -e "s|^LAYOUT PRIMARY .*|LAYOUT PRIMARY \"$top\"|" \
    -e "s|^LAYOUT PATH .*|LAYOUT PATH \"$gds\"|" \
    -e "s|^SOURCE PRIMARY .*|SOURCE PRIMARY \"$top\"|" \
    -e "s|^SOURCE PATH .*|SOURCE PATH \"$src\"|" \
    -e "s|^LVS POWER NAME .*|LVS POWER NAME \"$pwr\"|" \
    -e "s|^LVS GROUND NAME .*|LVS GROUND NAME \"$gnd\"\nSOURCE CASE YES\nLAYOUT CASE YES|" \
    -e "s|^ *SOURCE CASE .*||" -e "s|^ *LAYOUT CASE .*||" \
    -e "s|INCLUDE \./|INCLUDE $d/|" \
    "$deck"
