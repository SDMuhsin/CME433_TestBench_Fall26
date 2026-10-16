#!/usr/bin/env bash
# Open-source proxy of the standalone synthesis (NOT the 65 nm result): yosys + abc on the
# gf180mcu 7-track 3.3 V tt library, worst input -> output delay from OpenSTA, for a few abc
# delay targets.  Needs `source src/flow/env.sh`.
#   src_int8/approx/syn/oss_proxy.sh <variant> "<abc_delay_targets_ps>" [NAME=VALUE ...]
set -u
SRC=$(cd "$(dirname "$0")/../.." && pwd); ROOT=$(dirname "$SRC")
v=$1; targets=$2; shift 2
if [ "$v" = exact ]; then f=$SRC/rtl/int/mq_mul8.v; elif [ -f "$SRC/bench/variants/$v.v" ]; then f=$SRC/bench/variants/$v.v; else f=$v; fi
LIB=$(ls "$PDK_ROOT"/ciel/gf180mcu/versions/*/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3/lib/gf180mcu_as_sc_mcu7t3v3__tt_025C_3v30.lib | head -1)
tag=$(basename "$v" .v)$(for d in "$@"; do printf _%s "${d//=/}"; done)
OUT=$ROOT/build/approx/oss/$tag; mkdir -p "$OUT"
defs=$(for d in "$@"; do printf -- '-D%s ' "$d"; done)
for t in $targets; do
    yosys -q -l "$OUT/y_$t.log" -p "read_verilog $defs $f; synth -flatten -booth -top mq_mul8;
        abc -D $t -liberty $LIB; opt_clean; tee -q -o $OUT/stat_$t.txt stat -liberty $LIB;
        write_verilog -noattr $OUT/net_$t.v" >/dev/null 2>&1 || { echo "$tag $t yosys FAIL"; continue; }
    cat > "$OUT/sta_$t.tcl" <<STA
read_liberty $LIB
read_verilog $OUT/net_$t.v
link_design mq_mul8
set_input_delay 0 [all_inputs]
set_output_delay 0 [all_outputs]
set_load 0.02 [all_outputs]
report_checks -path_delay max -format end -unconstrained
STA
    sta -no_init -exit "$OUT/sta_$t.tcl" > "$OUT/sta_$t.log" 2>&1
    area=$(awk '/Chip area/ {print $NF; exit}' "$OUT/stat_$t.txt")
    dly=$(awk '/\(output\)/ {print $4; exit}' "$OUT/sta_$t.log")
    printf '%-26s abc_D %6s ps  area %9s um2  delay %s ns\n' "$tag" "$t" "$area" "$dly"
done
