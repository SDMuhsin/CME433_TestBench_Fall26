# PrimeTime STA of a gan65 DC netlist at one library corner (pre-layout, ideal clocks).
# Environment (set by sta/run_pt.csh): GAN65 MQ65 GAN65_SYN GAN65_CORNER (ss|tt|ff)
#   GAN65_RC (max|min|none) GAN65_PERIOD (ns) GAN65_OUT GAN65_TAG
# Latches: PrimeTime's default level-sensitive analysis (time borrowing up to the closing edge).
source $::env(GAN65)/syn/common/pt_load.tcl
source $::env(MQ65)/sta/latch_report.tcl

set out $::env(GAN65_OUT)
file mkdir $out/rpt
gan65_pt_load $::env(GAN65_SYN) $::env(GAN65_CORNER) $::env(GAN65_RC) $::env(GAN65_PERIOD)
update_timing -full

report_annotated_parasitics              > $out/rpt/annotated_parasitics.rpt
check_timing                             > $out/rpt/check_timing.rpt
report_timing -max_paths 5 -nosplit -input_pins -nets -transition_time > $out/rpt/timing_max.rpt
report_timing -delay_type min -max_paths 5 -nosplit > $out/rpt/timing_min.rpt
report_timing -to [all_registers -level_sensitive -data_pins] -max_paths 2 -nosplit > $out/rpt/timing_rf_wr.rpt
report_timing -through [mq65_latch_q_pins] -max_paths 2 -nosplit > $out/rpt/timing_rf_rd.rpt
report_constraint -all_violators -nosplit > $out/rpt/violators.rpt
report_global_timing                     > $out/rpt/global_timing.rpt

set fh [open $out/summary.txt w]
puts $fh "gan65_chip 65 nm PrimeTime summary ($::env(GAN65_TAG))"
puts $fh "netlist [file tail $::env(GAN65_SYN)]  corner $::env(GAN65_CORNER)  parasitics $::env(GAN65_RC)  period_ns $::env(GAN65_PERIOD)  clocks ideal (pre-layout)"
mq65_put_timing $fh
gan65_put_mul_timing $fh
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
