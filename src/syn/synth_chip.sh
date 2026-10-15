#!/usr/bin/env bash
# Yosys synthesis of the full mb_chip (gf180mcu_as_sc_mcu7t3v3, SRAM macros as black boxes)
# plus a pre-layout OpenSTA check at the slow corner (ss_125C_3v00, no wire load) vs 40 ns.
#   src/syn/synth_chip.sh [build_dir]      (default src/syn/build; needs yosys, sta, $PDK_ROOT)
# Fails on latches, comb loops / multi-driven nets, or negative setup slack.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
BUILD=${1:-$SRC/syn/build}
LIBDIR=$(ls -d "$PDK_ROOT"/ciel/gf180mcu/versions/*/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3/lib | head -1)
SRAMDIR=$ROOT/gf180mcu_ocd_ip_sram__sram256x8m8wm1
TT=$LIBDIR/gf180mcu_as_sc_mcu7t3v3__tt_025C_3v30.lib
SS=$LIBDIR/gf180mcu_as_sc_mcu7t3v3__ss_125C_3v00.lib
SRAM_LEF=$SRAMDIR/gf180mcu_ocd_ip_sram__sram256x8m8wm1.lef
SRAM_SS=$SRAMDIR/gf180mcu_ocd_ip_sram__sram256x8m8wm1__ss_125C_3v00.lib
PERIOD=${PERIOD:-40}
mkdir -p "$BUILD"
RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f" | tr '\n' ' ')
NL=$BUILD/mb_chip.nl.v

yosys -q -l "$BUILD/mb_chip.log" -p "
    read_verilog -DSYNTHESIS -I $SRC/rtl/nonlin -I $SRC/rtl/seq $RTL $SRC/rtl/mem/gf180_sram_macro.v
    synth -flatten -top mb_chip
    select -assert-none t:\$_DLATCH* t:\$dlatch* t:\$sr t:\$_SR*
    check -assert
    dfflibmap -liberty $TT
    abc -D $((PERIOD * 1000)) -liberty $TT
    hilomap -singleton -hicell gf180mcu_as_sc_mcu7t3v3__tieh_4 ONE -locell gf180mcu_as_sc_mcu7t3v3__tiel_4 ZERO
    delete t:\$scopeinfo
    opt_clean
    tee -o $BUILD/mb_chip.stat stat -liberty $TT
    write_verilog -noattr $NL" >/dev/null 2>&1 ||
    { echo "FAIL synth (see $BUILD/mb_chip.log)"; exit 1; }

cat > "$BUILD/sta.tcl" <<TCL
read_liberty $SS
read_liberty $SRAM_SS
read_verilog $NL
link_design mb_chip
create_clock -name clk -period $PERIOD [get_ports clk]
set_input_delay 0 -clock clk [delete_from_list [all_inputs] [get_ports clk]]
set_output_delay 0 -clock clk [all_outputs]
report_checks -path_delay max -group_path_count 1 -digits 2
set srams [get_cells -filter "ref_name == gf180mcu_ocd_ip_sram__sram256x8m8wm1" *]
puts "SRAM paths:"
report_checks -path_delay max -from \$srams -digits 2 -format end
report_checks -path_delay max -to \$srams -digits 2 -format end
report_checks -path_delay min -digits 2
report_wns
report_tns
TCL
sta -no_init -exit "$BUILD/sta.tcl" > "$BUILD/sta.rpt" 2>&1 || { echo "FAIL sta (see $BUILD/sta.rpt)"; exit 1; }

cells=$(awk '/cells$/ {print $1; exit}' "$BUILD/mb_chip.stat")
flops=$(grep -E '^ +[0-9]+ .*gf180mcu_as_sc_mcu7t3v3__(df|sdf)' "$BUILD/mb_chip.stat" | awk '{s+=$1} END {print s+0}')
srams=$(grep -E '^ +[0-9]+ .*gf180mcu_ocd_ip_sram__sram256x8m8wm1' "$BUILD/mb_chip.stat" | awk '{print $1}')
area=$(awk '/Chip area/ {printf "%.0f", $NF; exit}' "$BUILD/mb_chip.stat")
macro=$(awk -v n="${srams:-0}" '/^ *SIZE/ {printf "%.0f", n * $2 * $4; exit}' "$SRAM_LEF")
wns=$(awk '/^wns/ {print $NF}' "$BUILD/sta.rpt")
slack=$(awk '/slack \((MET|VIOLATED)\)/ {print $1; exit}' "$BUILD/sta.rpt")
echo "mb_chip: $cells std cells ($flops flops), std-cell area $area um^2; ${srams:-0} SRAM macros $macro um^2 (LEF)"
echo "pre-layout STA ss_125C_3v00 @ ${PERIOD} ns: worst setup slack $slack ns (wns $wns); path in $BUILD/sta.rpt"
awk -v s="$slack" 'BEGIN {exit !(s >= 0)}'
