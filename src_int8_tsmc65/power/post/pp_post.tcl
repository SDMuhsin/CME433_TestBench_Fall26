# Post-layout PrimeTime PX (averaged) power: routed netlist with its clock tree, extracted
# SPEF, propagated clocks, switching activity from a gate-level SAIF of the same netlist.
# Environment (set by power/post/run_power_post.csh):
#   MQ65 MQ65_NETLIST MQ65_SPEF MQ65_RCLABEL MQ65_CORNER MQ65_PERIOD MQ65_SAIF MQ65_OUT MQ65_TAG
source $::env(MQ65)/syn/common/pt_load.tcl
source $::env(MQ65)/power/power_digest.tcl
set out $::env(MQ65_OUT)
file mkdir $out/rpt
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
mq65_pt_load_post $::env(MQ65_NETLIST) $::env(MQ65_CORNER) $::env(MQ65_SPEF) $::env(MQ65_PERIOD)
read_saif -strip_path tb_mq_chip/dut $::env(MQ65_SAIF) > $out/rpt/read_saif.rpt
report_switching_activity                > $out/rpt/switching.rpt
report_switching_activity -list_not_annotated > $out/rpt/not_annotated.rpt
update_power
report_power -nosplit                    > $out/rpt/power.rpt
report_power -nosplit -hierarchy -levels 4 > $out/rpt/power_hier.rpt

set fh [open $out/summary.txt w]
puts $fh "mq_chip 65 nm post-layout power summary ($::env(MQ65_TAG))"
puts $fh "netlist routed  corner $::env(MQ65_CORNER)  parasitics $::env(MQ65_RCLABEL)  period_ns $::env(MQ65_PERIOD)  clocks propagated  activity SAIF (averaged)"
mq65_put_saif_window $fh $::env(MQ65_SAIF)
mq65_put_coverage $fh $out/rpt/read_saif.rpt $out/rpt/switching.rpt
mq65_put_power $fh $out/rpt/power.rpt
mq65_put_hier_power $fh
mq65_put_clock_net $fh
close $fh
exit
