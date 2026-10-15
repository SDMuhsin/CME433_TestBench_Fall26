#!/usr/bin/env bash
# Block-level DRC runset from the foundry deck (stdout):  runset.sh <deck> <gds> <top>
# Switches: chip-level and seal-ring checks off (core block, no pad ring / seal ring),
# GP process option on, action-required rules only (recommendations, guidelines and
# analog recommendations off).  Density rules stay on: the block has no dummy fill, which
# is inserted at chip assembly, so density results are listed separately as waived.
deck=$1; gds=$2; top=$3
sed -e "s|^LAYOUT PATH .*|LAYOUT PATH \"$gds\"|" \
    -e "s|^LAYOUT PRIMARY .*|LAYOUT PRIMARY \"$top\"|" \
    -e 's|^DRC RESULTS DATABASE .*|DRC RESULTS DATABASE "drc.results" ASCII|' \
    -e 's|^DRC SUMMARY REPORT .*|DRC SUMMARY REPORT "drc.sum" HIER|' \
    -e 's|^#DEFINE FULL_CHIP|//#DEFINE FULL_CHIP|' \
    -e 's|^#DEFINE WLCSP_SEALRING|//#DEFINE WLCSP_SEALRING|' \
    -e 's|^//#DEFINE GP |#DEFINE GP |' \
    -e 's|^#DEFINE \(Recommended\|Guideline\|Analog\|GUIDELINE_[A-Z]*\) |//#DEFINE \1 |' \
    "$deck"
