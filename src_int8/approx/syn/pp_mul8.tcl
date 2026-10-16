# PrimePower (averaged) of a standalone mq_mul8 netlist with SAIF from its timing simulation.
# Environment (set by run_power.csh): MQ65 MUL8_SYN MUL8_SAIF MUL8_PERIOD MUL8_CORNER MUL8_TAG
source $::env(MQ65)/syn/common/libs.tcl
set syn $::env(MUL8_SYN)
set corner $::env(MUL8_CORNER)
set period $::env(MUL8_PERIOD)
file mkdir rpt
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
set_app_var search_path [list . $::MQ65_LIBDIR]
set_app_var link_path [list * [mq65_db $corner]]
read_verilog $syn/mq_mul8.v
current_design mq_mul8
link_design mq_mul8
set_operating_conditions [mq65_oc $corner] -library [mq65_lib $corner]
read_sdc $syn/mq_mul8.sdc
if {![file exists $::env(MUL8_SAIF)]} { puts "Error: no SAIF $::env(MUL8_SAIF)"; exit 1 }
read_saif -strip_path tb_mul8_power/dut $::env(MUL8_SAIF) > rpt/read_saif.rpt
report_switching_activity > rpt/switching.rpt
update_power
report_power -nosplit > rpt/power.rpt

set d [current_design]
set fh [open summary.txt w]
puts $fh "mq_mul8 standalone power summary ($::env(MUL8_TAG))"
puts $fh "corner $corner  period_ns $period  activity SAIF from SDF timing simulation (averaged)"
foreach line [split [read [set f [open rpt/read_saif.rpt r]]] "\n"] {
    if {[regexp {^(Total|Number)} $line]} { puts $fh "saif: $line" }
}
close $f
foreach line [split [read [set f [open rpt/switching.rpt r]]] "\n"] {
    if {[regexp {^ Nets } $line] && ![info exists seen]} {
        set seen 1
        puts $fh "activity: [regsub -all {\s+} [string trim $line] { }]  (last two: not annotated, total)" }
}
close $f
foreach a {internal_power switching_power leakage_power total_power} {
    puts $fh [format "%-16s %.6e W" $a [get_attribute $d $a]]
}
puts $fh [format "energy_per_op_pJ %.6f" [expr {[get_attribute $d total_power] * $period * 1e3}]]
close $fh
exit
