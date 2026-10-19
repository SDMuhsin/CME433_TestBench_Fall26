# SDF of a mul_bench netlist for timing-annotated GLS (ideal root clock, as the STA).
# Environment (run_gls.csh): GAN65 MQ65 MB_SYN MB_CORNER MB_RC MB_PERIOD MB_SDF
source $::env(GAN65)/syn/mulbench/pt_load.tcl
mb_pt_load $::env(MB_SYN) $::env(MB_CORNER) $::env(MB_RC) $::env(MB_PERIOD)
set_ideal_network [get_ports clk]
update_timing -full
report_timing -max_paths 1 -nosplit > $::env(MB_SYN)/pt_timing_$::env(MB_CORNER).rpt
write_sdf -version 3.0 -context verilog $::env(MB_SDF)
exit
