# DC synthesis of one standalone mq_mul8 (combinational) on the 65 nm library of the mq65 flow.
# Environment (set by run_dc.csh):
#   MQ65        src_int8_tsmc65 directory (site config, library helpers)
#   MUL8_SRC    Verilog source file(s) of the variant      MUL8_DEFS  extra `define list
#   MUL8_CORNER ss | tt | ff                               MUL8_DELAY input -> output max delay, ns
#   MUL8_OUT    output directory (netlist, SDF, SDC, reports, summary.txt)
# Same environment as the chip run: inputs driven by the chip's input driver cell, outputs
# loaded with 4 x the reference load pin, wire-load model, compile_ultra with DesignWare.
source $::env(MQ65)/syn/common/libs.tcl
set corner $::env(MUL8_CORNER)
set delay  $::env(MUL8_DELAY)
set out    $::env(MUL8_OUT)
set lib    [mq65_lib $corner]
file mkdir $out/rpt
set_host_options -max_cores 1

set_app_var search_path [concat . $::MQ65_LIBDIR $search_path]
set_app_var target_library [list [mq65_db $corner]]
set_app_var synthetic_library dw_foundation.sldb
set_app_var link_library [list * [mq65_db $corner] dw_foundation.sldb]

define_design_lib WORK -path $out/work
analyze -format verilog -define [concat SYNTHESIS $::env(MUL8_DEFS)] $::env(MUL8_SRC)
elaborate mq_mul8
current_design mq_mul8
link

set_operating_conditions -max [mq65_oc $corner] -max_library $lib
set_wire_load_mode enclosed
set_wire_load_selection_group $::MQ65_WLM_GROUP
set_driving_cell -lib_cell [lindex $::MQ65_DRV_IN 0] -library $lib -pin [lindex $::MQ65_DRV_IN 1] [all_inputs]
set_load [expr {4.0 * [load_of $lib/$::MQ65_LOAD_PIN]}] [all_outputs]
set_max_delay $delay -from [all_inputs] -to [all_outputs]

compile_ultra
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output $out/mq_mul8.v
write_sdf -version 2.1 $out/mq_mul8.sdf
write_sdc $out/mq_mul8.sdc

report_area -nosplit                > $out/rpt/area.rpt
report_timing -max_paths 3 -nosplit > $out/rpt/timing.rpt
report_power -nosplit               > $out/rpt/power_default.rpt
report_qor                          > $out/rpt/qor.rpt

# summary (numbers only; safe to copy off the server)
set cells [get_cells -hierarchical -filter "is_hierarchical==false"]
set area 0.0
foreach_in_collection c $cells { set area [expr {$area + [get_attribute $c area]}] }
set nand2 [lindex [get_attribute [get_lib_cells */$::MQ65_NAND2] area] 0]
set p [get_timing_paths -delay_type max -max_paths 1]
redirect -variable rp {report_power -nosplit}
set fh [open $out/summary.txt w]
puts $fh "mq_mul8 standalone DC summary"
puts $fh "sources [join [lmap f $::env(MUL8_SRC) {file tail $f}]]  defines {$::env(MUL8_DEFS)}"
puts $fh [format "corner %s  max_delay_target_ns %s" $corner $delay]
puts $fh [format "cell_area_um2 %.2f" $area]
puts $fh [format "gate_equivalents %.1f" [expr {$area / $nand2}]]
puts $fh [format "leaf_cells %d" [sizeof_collection $cells]]
puts $fh [format "critical_delay_ns %.4f" [get_attribute $p arrival]]
puts $fh [format "slack_ns %.4f" [get_attribute $p slack]]
if {[regexp -line {^Total\s+(\S+ \S+)\s+(\S+ \S+)\s+(\S+ \S+)\s+(\S+ \S+)} $rp -> pi ps pl pt]} {
    puts $fh "dc_power internal $pi  switching $ps  leakage $pl  total $pt  (default activity)"
}
close $fh
exit
