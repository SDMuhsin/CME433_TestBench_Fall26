# Post-layout PrimeTime STA of the routed netlist: extracted SPEF, propagated clocks.
# Environment (set by sta/post/run_pt_post.csh):
#   MQ65 MQ65_NETLIST MQ65_SPEF MQ65_CORNER (ss|tt|ff) MQ65_RCLABEL MQ65_PERIOD MQ65_OUT MQ65_TAG
source $::env(MQ65)/syn/common/pt_load.tcl
source $::env(MQ65)/syn/common/summary.tcl
source $::env(MQ65)/sta/latch_report.tcl
source $::env(MQ65)/sta/post/clock_report.tcl

set out $::env(MQ65_OUT)
file mkdir $out/rpt
mq65_pt_load_post $::env(MQ65_NETLIST) $::env(MQ65_CORNER) $::env(MQ65_SPEF) $::env(MQ65_PERIOD)
update_timing -full

report_annotated_parasitics              > $out/rpt/annotated_parasitics.rpt
check_timing                             > $out/rpt/check_timing.rpt
report_timing -max_paths 5 -nosplit -input_pins -nets -transition_time > $out/rpt/timing_max.rpt
report_timing -delay_type min -max_paths 5 -nosplit > $out/rpt/timing_min.rpt
report_constraint -all_violators -nosplit > $out/rpt/violators.rpt
report_global_timing                     > $out/rpt/global_timing.rpt
report_clock_timing -type skew -nworst 5 -nosplit > $out/rpt/clock_skew.rpt
report_clock_timing -type latency -nworst 5 -nosplit > $out/rpt/clock_latency.rpt

set fh [open $out/summary.txt w]
puts $fh "mq_chip 65 nm post-layout PrimeTime summary ($::env(MQ65_TAG))"
puts $fh "netlist routed  corner $::env(MQ65_CORNER)  parasitics $::env(MQ65_RCLABEL)  period_ns $::env(MQ65_PERIOD)  clocks propagated"
mq65_put_timing $fh
mq65_put_latch $fh
mq65_put_clock_tree $fh
set fc [open $out/rpt/violators.rpt r]; set nviol [regexp -all {VIOLATED} [read $fc]]; close $fc
puts $fh "report_constraint VIOLATED groups: $nviol (rpt/violators.rpt)"
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
