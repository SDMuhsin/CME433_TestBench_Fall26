# Formality: RTL (reference) vs DC netlist (implementation) with the DC guidance file (SVF).
# Environment (set by lec/run_fm.csh): GAN65 MQ65 GAN65_SYN (DC output dir) GAN65_CORNER
#   GAN65_MUL_F (multiplier sources of that DC run) GAN65_OUT GAN65_TAG
# Reference = exactly the RTL DC read (rtl/gan65.f, site ICG wrapper, the run's multiplier).
source $::env(GAN65)/syn/common/flow.tcl
set syn $::env(GAN65_SYN)
set out $::env(GAN65_OUT)
file mkdir $out/rpt
set_host_options -max_cores 8

set_app_var synopsys_auto_setup true
# DC -gate_clock inserted latch-based integrated clock gates that are not in the RTL
set_app_var verification_clock_gate_hold_mode any
set_svf $syn/gan65_chip.svf

read_db -technology_library [mq65_db $::env(GAN65_CORNER)]
set_app_var search_path [concat . [gan65_rtl_incdirs]]
read_verilog -container r -libname WORK -05 [gan65_rtl_files]
set_top r:/WORK/gan65_chip
read_verilog -container i -libname WORK -05 $syn/gan65_chip.v
set_top i:/WORK/gan65_chip

match
report_unmatched_points                  > $out/rpt/unmatched.rpt
set_app_var verification_failing_point_limit 0
set ok [verify]
report_status                            > $out/rpt/status.rpt
report_failing_points                    > $out/rpt/failing.rpt
report_aborted_points                    > $out/rpt/aborted.rpt
report_unverified_points                 > $out/rpt/unverified.rpt
report_guidance -summary                 > $out/rpt/guidance.rpt
if {!$ok} { analyze_points -failing      > $out/rpt/analyze.rpt }
source $::env(GAN65)/lec/fm_summary.tcl
gan65_fm_summary $out $syn $ok
exit
