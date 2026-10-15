# DC synthesis of mq_chip on the 65 nm standard-cell library (compile_ultra, DesignWare, clock gating).
# Environment (set by run_dc.csh):
#   MQ65          server tree (~/mq65)
#   MQ65_PERIOD   clock period, ns            (default 40)
#   MQ65_TOPO     1 = topographical mode (Milkyway + TLU+), 0 = wire-load model
#   MQ65_OUT      output directory (netlist, ddc, svf, reports, summary)
# Setup corner ss with ff as min library for hold fixing.

source $::env(MQ65)/syn/common/libs.tcl
source $::env(MQ65)/syn/common/rtl.tcl
source $::env(MQ65)/syn/common/summary.tcl

set period [expr {[info exists ::env(MQ65_PERIOD)] ? $::env(MQ65_PERIOD) : 40}]
set topo   [expr {[info exists ::env(MQ65_TOPO)] ? $::env(MQ65_TOPO) : 1}]
set out    $::env(MQ65_OUT)
file mkdir $out/rpt
set_host_options -max_cores 8

# ---------------------------------------------------------------- libraries
set_app_var search_path [concat . $::MQ65_LIBDIR [mq65_rtl_incdirs] $search_path]
set_app_var target_library [list [mq65_db ss]]
set_app_var synthetic_library dw_foundation.sldb
set_app_var link_library [list * [mq65_db ss] dw_foundation.sldb]
set_min_library [mq65_db ss] -min_version [mq65_db ff]
if {$topo} {
    set mw $out/mq65_mw
    file delete -force $mw
    create_mw_lib -technology $::MQ65_TF -mw_reference_library $::MQ65_MW_REF $mw
    open_mw_lib $mw
    mq65_rc_setup
}
set_svf $out/mq_chip.svf

# ---------------------------------------------------------------- read RTL
define_design_lib WORK -path $out/work
set_app_var hdlin_preserve_sequential true
analyze -format verilog -define {SYNTHESIS} [mq65_rtl_files]
elaborate mq_chip
current_design mq_chip
link

# ---------------------------------------------------------------- constraints
set ::mq_period $period
set ::mq_lib [mq65_lib ss]
set_operating_conditions -max [mq65_oc ss] -max_library [mq65_lib ss] \
                         -min [mq65_oc ff] -min_library [mq65_lib ff]
if {!$topo} {
    set_wire_load_mode enclosed
    set_wire_load_selection_group $::MQ65_WLM_GROUP
}
source $::env(MQ65)/syn/constraints/mq65.sdc
set_fix_hold [get_clocks clk]
# constant pad-control outputs: no buffering
set_app_var compile_seqmap_propagate_constants true

# clock gating of enabled flop banks (RF word gates are explicit library ICG cells, site/mq65_icg_site.v)
set_clock_gating_style -sequential_cell latch -positive_edge_logic integrated \
    -control_point before -minimum_bitwidth 4 -max_fanout 32
# keep the memory hierarchy (one RF per former macro) visible for reporting
set_ungroup [get_designs mq65_latch_rf*] false
set_ungroup [get_designs mq_sram_256x8*] false

# ---------------------------------------------------------------- compile
# no retiming: the netlist keeps the RTL register boundaries (Formality, per-unit reporting)
compile_ultra -no_autoungroup -gate_clock
if {$period < 10.0} { compile_ultra -incremental -no_autoungroup }

# ---------------------------------------------------------------- outputs
change_names -rules verilog -hierarchy
write -format ddc -hierarchy -output $out/mq_chip.ddc
write -format verilog -hierarchy -output $out/mq_chip.v
write_sdc $out/mq_chip.sdc
set_svf -off

report_qor                              > $out/rpt/qor.rpt
report_area -hierarchy -nosplit          > $out/rpt/area_hier.rpt
report_area -nosplit                     > $out/rpt/area.rpt
report_timing -max_paths 5 -nosplit      > $out/rpt/timing_max.rpt
report_timing -delay_type min -max_paths 5 -nosplit > $out/rpt/timing_min.rpt
report_constraint -all_violators -nosplit > $out/rpt/violators.rpt
report_clock_gating -nosplit             > $out/rpt/clock_gating.rpt
report_power -nosplit                    > $out/rpt/power_default.rpt
report_hierarchy -noleaf                 > $out/rpt/hierarchy.rpt
mq65_summary $out/summary.txt $period $topo
exit
