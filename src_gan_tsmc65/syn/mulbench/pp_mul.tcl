# PrimePower (averaged) of a mul_bench netlist with the SAIF of an SDF-timed GLS.
# Environment (run_power.csh): GAN65 MQ65 MB_SYN MB_CORNER MB_RC MB_PERIOD MB_SAIF MB_OUT MB_TAG
source $::env(GAN65)/syn/mulbench/pt_load.tcl
set out $::env(MB_OUT)
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
mb_pt_load $::env(MB_SYN) $::env(MB_CORNER) $::env(MB_RC) $::env(MB_PERIOD)
read_saif -strip_path tb_mul_saif/dut $::env(MB_SAIF) > $out/read_saif.rpt
update_power
report_power -nosplit > $out/power.rpt
report_power -nosplit -hierarchy -levels 2 > $out/power_hier.rpt
set fh [open $out/summary.txt w]
puts $fh "mul_bench power ($::env(MB_TAG))  corner $::env(MB_CORNER)  rc $::env(MB_RC)  period_ns $::env(MB_PERIOD)  SAIF from SDF-timed GLS (glitches counted)"
set f [open $out/read_saif.rpt r]
foreach l [split [read $f] "\n"] { if {[regexp {^(Total|Number)} $l]} { puts $fh "  saif: $l" } }
close $f
foreach {lbl obj} [list total [current_design] mul [get_cells u_mul]] {
    puts $fh [format "%-5s internal %.6e  switching %.6e  leakage %.6e  total %.6e W" $lbl \
        [get_attribute $obj internal_power] [get_attribute $obj switching_power] \
        [get_attribute $obj leakage_power] [get_attribute $obj total_power]]
}
puts $fh [format "energy_per_op_pJ mul %.4f  total %.4f  (power x period, one product per clock)" \
    [expr {[get_attribute [get_cells u_mul] total_power] * $::env(MB_PERIOD) * 1e3}] \
    [expr {[get_attribute [current_design] total_power] * $::env(MB_PERIOD) * 1e3}]]
close $fh
exit
