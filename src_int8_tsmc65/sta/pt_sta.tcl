# PrimeTime STA of a DC netlist at one library corner (pre-layout, ideal clocks).
# Environment (set by sta/run_pt.csh):
#   MQ65 MQ65_SYN (DC output dir)  MQ65_CORNER (ss|tt|ff)  MQ65_RC (max|min|none)
#   MQ65_PERIOD (ns)  MQ65_OUT (output dir)  MQ65_TAG (summary name)
# Latches: PrimeTime's default level-sensitive analysis (time borrowing up to the closing
# edge, the borrowed time charged to the paths launched from the latch).
source $::env(MQ65)/syn/common/pt_load.tcl
source $::env(MQ65)/syn/common/summary.tcl
source $::env(MQ65)/sta/latch_report.tcl

set out $::env(MQ65_OUT)
file mkdir $out/rpt
mq65_pt_load $::env(MQ65_SYN) $::env(MQ65_CORNER) $::env(MQ65_RC) $::env(MQ65_PERIOD)
update_timing -full

report_annotated_parasitics              > $out/rpt/annotated_parasitics.rpt
check_timing                             > $out/rpt/check_timing.rpt
check_timing -verbose                    > $out/rpt/check_timing_verbose.rpt
report_timing -max_paths 5 -nosplit -input_pins -nets -transition_time > $out/rpt/timing_max.rpt
report_timing -delay_type min -max_paths 5 -nosplit > $out/rpt/timing_min.rpt
report_timing -to [all_registers -level_sensitive -data_pins] -max_paths 2 -nosplit > $out/rpt/timing_rf_wr.rpt
report_timing -through [mq65_latch_q_pins] -max_paths 2 -nosplit > $out/rpt/timing_rf_rd.rpt
report_constraint -all_violators -nosplit > $out/rpt/violators.rpt
report_global_timing                     > $out/rpt/global_timing.rpt
report_disable_timing                    > $out/rpt/disable_timing.rpt

set fh [open $out/summary.txt w]
puts $fh "mq_chip 65 nm PrimeTime summary ($::env(MQ65_TAG))"
puts $fh "netlist [file tail $::env(MQ65_SYN)]  corner $::env(MQ65_CORNER)  parasitics $::env(MQ65_RC)  period_ns $::env(MQ65_PERIOD)  clocks ideal (pre-layout)"
mq65_put_timing $fh
mq65_put_latch $fh
puts $fh "check_timing:"
set fc [open $out/rpt/check_timing.rpt r]
foreach line [split [read $fc] "\n"] { if {[regexp {^(Warning|Error|Information)} $line]} { puts $fh "  $line" } }
close $fc
puts $fh "parasitics annotation:"
set fc [open $out/rpt/annotated_parasitics.rpt r]
foreach line [split [read $fc] "\n"] { if {[string first "|" $line] >= 0} { puts $fh "  $line" } }
close $fc
close $fh
exit
