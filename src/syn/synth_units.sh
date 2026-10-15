#!/usr/bin/env bash
# Yosys synthesis sanity check of every datapath unit: no latches, no comb loops /
# multi-driven nets, gf180mcu_as_sc_mcu7t3v3 (tt) cell count and area.
#   src/syn/synth_units.sh [build_dir]     (default src/syn/build; needs yosys and $PDK_ROOT)
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
BUILD=${1:-$SRC/syn/build}
LIB=${LIB:-$(ls "$PDK_ROOT"/ciel/gf180mcu/versions/*/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3/lib/gf180mcu_as_sc_mcu7t3v3__tt_025C_3v30.lib | head -1)}
mkdir -p "$BUILD"
RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/units.f" | tr '\n' ' ')
fail=0
printf '%-18s %8s %8s %12s  %s\n' unit cells flops 'area_um2' status
for top in mb_fp16_mul mb_fp16_to_fp32 mb_fp32_add_rne mb_fp32_wb mb_lane \
           mb_nlu_addr mb_nlu_frac mb_nlu_rom mb_nlu; do
    log="$BUILD/$top.log"
    yosys -q -l "$log" -p "
        read_verilog -I $SRC/rtl/nonlin $RTL
        synth -flatten -top $top
        select -assert-none t:\$_DLATCH* t:\$dlatch* t:\$sr t:\$_SR*
        check -assert
        dfflibmap -liberty $LIB
        abc -D 40000 -liberty $LIB
        delete t:\$scopeinfo
        opt_clean
        tee -o $BUILD/$top.stat stat -liberty $LIB" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        printf '%-18s %8s %8s %12s  %s\n' "$top" - - - "FAIL (see $log)"; fail=1; continue
    fi
    cells=$(awk '/cells$/ {print $1; exit}' "$BUILD/$top.stat")
    flops=$(grep -E '^ +[0-9]+ .*gf180mcu_as_sc_mcu7t3v3__df' "$BUILD/$top.stat" | awk '{s+=$1} END {print s+0}')
    area=$(awk '/Chip area/ {print $NF; exit}' "$BUILD/$top.stat")
    printf '%-18s %8s %8s %12s  %s\n' "$top" "$cells" "$flops" "$area" PASS
done
exit $fail
