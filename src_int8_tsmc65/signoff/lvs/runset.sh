#!/usr/bin/env bash
# Block-level LVS runset from the foundry deck (stdout):
#   runset.sh <deck> <gds> <source_netlist> <top> <power_net> <ground_net>
deck=$1; gds=$2; src=$3; top=$4; pwr=$5; gnd=$6
d=$(dirname "$deck")
sed -e "s|^LAYOUT PRIMARY .*|LAYOUT PRIMARY \"$top\"|" \
    -e "s|^LAYOUT PATH .*|LAYOUT PATH \"$gds\"|" \
    -e "s|^SOURCE PRIMARY .*|SOURCE PRIMARY \"$top\"|" \
    -e "s|^SOURCE PATH .*|SOURCE PATH \"$src\"|" \
    -e "s|^LVS POWER NAME .*|LVS POWER NAME \"$pwr\"|" \
    -e "s|^LVS GROUND NAME .*|LVS GROUND NAME \"$gnd\"|" \
    -e "s|INCLUDE \./|INCLUDE $d/|" \
    "$deck"
