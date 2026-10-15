# PrimeTime PX (averaged) power of a DC netlist with switching activity from gate-level SAIF.
# Environment (set by power/run_power.csh):
#   MQ65 MQ65_SYN MQ65_CORNER MQ65_RC MQ65_PERIOD MQ65_SAIF MQ65_OUT MQ65_TAG
source $::env(MQ65)/syn/common/pt_load.tcl
source $::env(MQ65)/power/power_digest.tcl
set out $::env(MQ65_OUT)
file mkdir $out/rpt
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
mq65_pt_load $::env(MQ65_SYN) $::env(MQ65_CORNER) $::env(MQ65_RC) $::env(MQ65_PERIOD)
read_saif -strip_path tb_mq_chip/dut $::env(MQ65_SAIF) > $out/rpt/read_saif.rpt
report_switching_activity                > $out/rpt/switching.rpt
report_switching_activity -list_not_annotated -nosplit > $out/rpt/not_annotated.rpt
update_power
report_power -nosplit                    > $out/rpt/power.rpt
report_power -nosplit -hierarchy -levels 4 > $out/rpt/power_hier.rpt

set fh [open $out/summary.txt w]
puts $fh "mq_chip 65 nm power summary ($::env(MQ65_TAG))"
puts $fh "netlist [file tail $::env(MQ65_SYN)]  corner $::env(MQ65_CORNER)  parasitics $::env(MQ65_RC)  period_ns $::env(MQ65_PERIOD)  activity SAIF (averaged)"
mq65_put_saif_window $fh $::env(MQ65_SAIF)
mq65_put_coverage $fh $out/rpt/switching.rpt
mq65_put_power $fh $out/rpt/power.rpt
mq65_put_hier_power $fh
close $fh
exit
