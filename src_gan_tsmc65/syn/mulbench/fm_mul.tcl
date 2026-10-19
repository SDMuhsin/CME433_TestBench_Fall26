# Formality: mul_bench RTL (reference, the files and define DC read) vs the DC netlist, with
# the DC guidance file. Environment (run_fm.csh): GAN65 MQ65 MB_N MB_DESIGN MB_SYN MB_CORNER MB_OUT
source $::env(GAN65)/syn/mulbench/common.tcl
set syn $::env(MB_SYN)
set out $::env(MB_OUT)
set_host_options -max_cores 4
set_app_var synopsys_auto_setup true
set_app_var verification_clock_gate_hold_mode any
set_svf $syn/mul_bench.svf
read_db -technology_library [mq65_db $::env(MB_CORNER)]
read_verilog -container r -libname WORK -05 -define [mb_define] [mb_rtl_files]
set_top r:/WORK/mul_bench
read_verilog -container i -libname WORK -05 $syn/mul_bench.v
set_top i:/WORK/mul_bench
match
set_app_var verification_failing_point_limit 0
set ok [verify]
report_status > $out/status.rpt
set fh [open $out/summary.txt w]
puts $fh "mul_bench Formality [file tail $syn]  verify_return $ok"
set f [open $out/status.rpt r]
foreach l [split [read $f] "\n"] {
    if {[regexp {(Verification|Passing|Failing|Aborted|Unverified)} $l]} { puts $fh "  $l" }
}
close $f
close $fh
exit
