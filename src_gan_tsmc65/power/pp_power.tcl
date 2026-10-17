# PrimePower (averaged mode) of a gan65 DC netlist with switching activity from a gate-level
# SAIF of one Fashion-MNIST image (sim/gls/run_gls.csh ... saif=1).
# Environment (set by power/run_power.csh):
#   GAN65 MQ65 GAN65_SYN GAN65_CORNER GAN65_RC GAN65_PERIOD GAN65_SAIF GAN65_ACT GAN65_CLK_IMG
#   GAN65_OUT GAN65_TAG
source $::env(GAN65)/syn/common/pt_load.tcl
source $::env(MQ65)/power/power_digest.tcl
source $::env(GAN65)/power/power_split.tcl
set out $::env(GAN65_OUT)
file mkdir $out/rpt
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
gan65_pt_load $::env(GAN65_SYN) $::env(GAN65_CORNER) $::env(GAN65_RC) $::env(GAN65_PERIOD)
read_saif -strip_path gan65_bench_tb/dut $::env(GAN65_SAIF) > $out/rpt/read_saif.rpt
report_switching_activity                > $out/rpt/switching.rpt
report_switching_activity -list_not_annotated > $out/rpt/not_annotated.rpt
update_power
report_power -nosplit                    > $out/rpt/power.rpt
report_power -nosplit -hierarchy -levels 4 > $out/rpt/power_hier.rpt

set fh [open $out/summary.txt w]
puts $fh "gan65_chip 65 nm power summary ($::env(GAN65_TAG))"
puts $fh "netlist [file tail $::env(GAN65_SYN)]  corner $::env(GAN65_CORNER)  parasitics $::env(GAN65_RC)  period_ns $::env(GAN65_PERIOD)  clocks ideal (pre-layout)"
puts $fh "mode averaged  activity $::env(GAN65_ACT)"
mq65_put_saif_window $fh $::env(GAN65_SAIF)
mq65_put_coverage $fh $out/rpt/read_saif.rpt $out/rpt/switching.rpt
mq65_put_power $fh $out/rpt/power.rpt
gan65_put_power_split $fh
gan65_put_energy $fh $::env(GAN65_PERIOD) $::env(GAN65_CLK_IMG)
mq65_put_clock_net $fh
close $fh
exit
