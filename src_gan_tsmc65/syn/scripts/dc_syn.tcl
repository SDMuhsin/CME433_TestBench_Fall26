# DC topographical synthesis of gan65_chip on the 65 nm standard-cell library
# (compile_ultra, DesignWare, clock gating), same recipe as src_int8_tsmc65/syn/scripts/dc_syn.tcl.
# Environment (set by run_dc.csh):
#   GAN65 / MQ65   src_gan_tsmc65 / src_int8_tsmc65 directories of the repository clone
#   GAN65_PERIOD   clock period, ns
#   GAN65_CORNER   ss | tt | ff: target library and RC corner
#   GAN65_MUL_F    multiplier source list (variant), GAN65_VARIANT its name
#   GAN65_WIDTH    datapath width 8 | 16 (include dir rtl/cfg/w<W>)
#   GAN65_OUT      output directory (netlist, ddc, svf, spef, reports, summary)
# Max library = the corner, min library ff for hold fixing (none in the ff run).

source $::env(GAN65)/syn/common/flow.tcl

set period $::env(GAN65_PERIOD)
set corner $::env(GAN65_CORNER)
set out    $::env(GAN65_OUT)
file mkdir $out/rpt
set_host_options -max_cores 8

# ---------------------------------------------------------------- libraries
set_app_var search_path [concat . $::MQ65_LIBDIR [gan65_rtl_incdirs] $search_path]
set_app_var target_library [list [mq65_db $corner]]
set_app_var synthetic_library dw_foundation.sldb
set_app_var link_library [list * [mq65_db $corner] dw_foundation.sldb]
if {$corner ne "ff"} { set_min_library [mq65_db $corner] -min_version [mq65_db ff] }
set mw $out/gan65_mw
file delete -force $mw
create_mw_lib -technology $::MQ65_TF -mw_reference_library $::MQ65_MW_REF $mw
open_mw_lib $mw
mq65_rc_setup $corner ff
set_svf $out/gan65_chip.svf

# ---------------------------------------------------------------- read RTL
define_design_lib WORK -path $out/work
set_app_var hdlin_preserve_sequential true
analyze -format verilog -define {SYNTHESIS} [gan65_rtl_files]
elaborate gan65_chip
current_design gan65_chip
link

# ---------------------------------------------------------------- constraints
set ::mq_period $period
set ::mq_lib [mq65_lib $corner]
set_operating_conditions -max [mq65_oc $corner] -max_library [mq65_lib $corner] \
                         -min [mq65_oc ff] -min_library [mq65_lib ff]
source $::env(MQ65)/syn/constraints/mq65.sdc
set_fix_hold [get_clocks clk]
# DC's hold fixing stalls a few ps short of zero on some short flop-to-flop paths (ff); a
# 30 ps larger hold uncertainty in compile reduces what is left. Reports below use 50 ps.
set_clock_uncertainty -hold [expr {$mq_unc_hold + 0.03}] [get_clocks clk]
set_app_var compile_seqmap_propagate_constants true

# clock gating of enabled flop banks (RF word gates are explicit library ICG cells)
set_clock_gating_style -sequential_cell latch -positive_edge_logic integrated \
    -control_point before -minimum_bitwidth 4 -max_fanout 32
# keep the PE / multiplier and memory hierarchies visible for per-block area reporting
foreach d {gan_mul* dla_pe* gan65_latch_rf* dla_sram_1rw_256x8*} {
    set ds [get_designs -quiet $d]
    if {[sizeof_collection $ds]} { set_ungroup $ds false }
}
# the multiplier is a closed block (no logic moved across its ports), so its cell area is
# the variant's own and comparable between variants
set_boundary_optimization [get_designs gan_mul*] false

# ---------------------------------------------------------------- compile
# no retiming: the netlist keeps the RTL register boundaries (Formality, per-unit reporting)
compile_ultra -no_autoungroup -gate_clock
compile_ultra -incremental -no_autoungroup

# reports, SDC and summary against the signoff constraints
set_clock_uncertainty -hold $mq_unc_hold [get_clocks clk]

# ---------------------------------------------------------------- outputs
change_names -rules verilog -hierarchy
write -format ddc -hierarchy -output $out/gan65_chip.ddc
write -format verilog -hierarchy -output $out/gan65_chip.v
write_sdc $out/gan65_chip.sdc
# estimated parasitics for PrimeTime (topographical virtual routing; max = this corner's RC, min = best RC)
write_parasitics -output $out/gan65_chip.max.spef
write_parasitics -min -output $out/gan65_chip.min.spef
set_svf -off

report_qor                              > $out/rpt/qor.rpt
report_area -hierarchy -nosplit          > $out/rpt/area_hier.rpt
report_area -nosplit                     > $out/rpt/area.rpt
report_timing -max_paths 5 -nosplit      > $out/rpt/timing_max.rpt
report_timing -delay_type min -max_paths 5 -nosplit > $out/rpt/timing_min.rpt
# worst path through a multiplier output (the variant's critical path inside the MAC)
set mul_p [get_pins -of_objects [get_cells -hierarchical -filter "is_hierarchical==true && full_name=~u_dla/u_pe_array/*u_pe/u_mul"] -filter "direction==out"]
report_timing -through $mul_p -max_paths 2 -nosplit > $out/rpt/timing_mul.rpt
report_constraint -all_violators -nosplit > $out/rpt/violators.rpt
check_timing                             > $out/rpt/check_timing.rpt
report_timing -to [all_registers -level_sensitive -data_pins] -max_paths 2 -nosplit > $out/rpt/timing_rf_wr.rpt
report_timing -through [all_registers -level_sensitive -output_pins] -max_paths 2 -nosplit > $out/rpt/timing_rf_rd.rpt
report_clock_gating -nosplit             > $out/rpt/clock_gating.rpt
report_power -nosplit                    > $out/rpt/power_default.rpt
report_hierarchy -noleaf                 > $out/rpt/hierarchy.rpt
gan65_summary $out/summary.txt $period $corner $::env(GAN65_VARIANT)
exit
