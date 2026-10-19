# DC topographical synthesis of mul_bench (N-bit multiplier between registers) with the chip
# flow's recipe (syn/scripts/dc_syn.tcl: ss target, ff min library, mq65.sdc, compile_ultra
# -no_autoungroup -gate_clock + incremental, multiplier hierarchy kept with no boundary
# optimisation). Environment (run_dc.csh): GAN65 MQ65 MB_N MB_DESIGN MB_PERIOD MB_CORNER MB_OUT
source $::env(GAN65)/syn/mulbench/common.tcl
source $::env(GAN65)/syn/mulbench/summary.tcl
set period $::env(MB_PERIOD)
set corner $::env(MB_CORNER)
set out    $::env(MB_OUT)
file mkdir $out/rpt
set_host_options -max_cores 4

set_app_var search_path [concat . $::MQ65_LIBDIR $search_path]
set_app_var target_library [list [mq65_db $corner]]
set_app_var synthetic_library dw_foundation.sldb
set_app_var link_library [list * [mq65_db $corner] dw_foundation.sldb]
if {$corner ne "ff"} { set_min_library [mq65_db $corner] -min_version [mq65_db ff] }
set mw $out/mb_mw
file delete -force $mw
create_mw_lib -technology $::MQ65_TF -mw_reference_library $::MQ65_MW_REF $mw
open_mw_lib $mw
mq65_rc_setup $corner ff
set_svf $out/mul_bench.svf

define_design_lib WORK -path $out/work
set_app_var hdlin_preserve_sequential true
analyze -format verilog -define [list SYNTHESIS [mb_define]] [mb_rtl_files]
elaborate mul_bench
current_design mul_bench
link

set ::mq_period $period
set ::mq_lib [mq65_lib $corner]
set_operating_conditions -max [mq65_oc $corner] -max_library [mq65_lib $corner] \
                         -min [mq65_oc ff] -min_library [mq65_lib ff]
source $::env(MQ65)/syn/constraints/mq65.sdc
set_fix_hold [get_clocks clk]
set_clock_uncertainty -hold [expr {$mq_unc_hold + 0.03}] [get_clocks clk]
set_app_var compile_seqmap_propagate_constants true
set_clock_gating_style -sequential_cell latch -positive_edge_logic integrated \
    -control_point before -minimum_bitwidth 4 -max_fanout 32
set core [get_designs mul_core*]
set_ungroup $core false
set_boundary_optimization $core false

compile_ultra -no_autoungroup -gate_clock
compile_ultra -incremental -no_autoungroup
set_clock_uncertainty -hold $mq_unc_hold [get_clocks clk]

change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output $out/mul_bench.v
write_sdc $out/mul_bench.sdc
write_parasitics -output $out/mul_bench.max.spef
write_parasitics -min -output $out/mul_bench.min.spef
set_svf -off

report_qor                               > $out/rpt/qor.rpt
report_area -hierarchy -nosplit          > $out/rpt/area_hier.rpt
report_timing -through [get_pins -of_objects [get_cells u_mul] -filter "direction==out"] \
    -max_paths 1 -nosplit                > $out/rpt/timing_mul.rpt
report_timing -delay_type min -max_paths 2 -nosplit > $out/rpt/timing_min.rpt
report_constraint -all_violators -nosplit > $out/rpt/violators.rpt
mb_summary $out/summary.txt $period $corner
exit
