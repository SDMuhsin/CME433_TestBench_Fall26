# Shared ICC2 helpers for the mq65 place-and-route stages (pnr/<stage>/<stage>.tcl).
# Environment (set by pnr/run_pnr.csh):
#   MQ65        src_int8_tsmc65 directory      MQ65_SYN  DC output dir (netlist)
#   MQ65_PNR    run directory (holds mq65.nlib, rpt/, out/)
#   MQ65_PERIOD clock period, ns                MQ65_UTIL target core utilisation
# The working block is always mq_chip; each stage ends with a snapshot mq_chip_<stage>, and
# a stage starts from the previous stage's snapshot (so any stage can be re-run).
source $::env(MQ65)/syn/common/libs.tcl

proc mq65_lib_path {} { return $::env(MQ65_PNR)/mq65.nlib }
proc mq65_ndm {} { return $::env(MQ65)/build/pnr/ndm/mq65_std.ndm }
proc mq65_rpt {name} { file mkdir $::env(MQ65_PNR)/rpt; return $::env(MQ65_PNR)/rpt/$name }

proc mq65_host {} { set_host_options -max_cores 8 }

# restore the previous stage's snapshot into the working block mq_chip
proc mq65_open_stage {from} {
    mq65_host
    open_lib [mq65_lib_path]
    copy_block -from_block mq_chip_$from -to_block mq_chip -force
    current_block mq_chip
    link_block
}

# save the working block and its snapshot mq_chip_<stage>
proc mq65_save_stage {stage} {
    save_block
    copy_block -from_block mq_chip -to_block mq_chip_$stage -force
    save_lib -all
}

# library cell restrictions: physical-only / special cells excluded from optimisation,
# clock buffers / inverters reserved for CTS
proc mq65_cell_usage {} {
    foreach p $::MQ65_DONT_USE {
        set c [get_lib_cells -quiet */$p]
        if {[sizeof_collection $c]} { set_dont_use $c }
    }
    foreach p $::MQ65_TIE {
        set c [get_lib_cells -quiet */$p]
        if {[sizeof_collection $c]} { set_lib_cell_purpose -include optimization $c }
    }
    set cts {}
    foreach p $::MQ65_CTS_CELLS { append_to_collection cts [get_lib_cells -quiet */$p] }
    set_lib_cell_purpose -exclude cts [get_lib_cells */*]
    set_lib_cell_purpose -include cts $cts
}

# MCMM setup: one functional mode, three corners with their library PVT and RC model
#   ss: setup (worst RC)   ff: hold (best RC)   tt: typical RC, reported only
# Same constraints as synthesis (syn/constraints/mq65.sdc); the driving cell / load
# lookups use the reference library name.
proc mq65_scenarios {} {
    foreach c {ss tt ff} {
        read_parasitic_tech -tlup [mq65_tlu $c] -layermap $::MQ65_TLU_MAP -name rc_$c
    }
    create_mode func
    foreach c {ss tt ff} {
        create_corner $c
        set_parasitic_parameters -corner $c -late_spec rc_$c -early_spec rc_$c
        lassign $::MQ65_CORNER_PVT($c) v t
        set_voltage $v -corner $c -object_list [get_supply_nets [lindex $::MQ65_PG 0]]
        set_voltage 0.0 -corner $c -object_list [get_supply_nets [lindex $::MQ65_PG 1]]
        set_temperature $t -corner $c
        set_process_number 1.0 -corner $c
        create_scenario -mode func -corner $c -name func_$c
    }
    foreach c {ss tt ff} {
        current_scenario func_$c
        set ::mq_period $::env(MQ65_PERIOD)
        set ::mq_lib mq65_std
        source $::env(MQ65)/syn/constraints/mq65.sdc
    }
    set_scenario_status func_ss -active true -setup true  -hold false -leakage_power true  -dynamic_power true  -max_transition true -max_capacitance true
    set_scenario_status func_tt -active true -setup true  -hold false -leakage_power false -dynamic_power false -max_transition false -max_capacitance false
    set_scenario_status func_ff -active true -setup false -hold true  -leakage_power false -dynamic_power false -max_transition true -max_capacitance true
    current_scenario func_ss
}

# per-stage report set (QoR, timing per scenario, utilisation, congestion)
proc mq65_stage_reports {stage} {
    report_qor -summary                              > [mq65_rpt ${stage}_qor.rpt]
    report_timing -scenarios func_ss -max_paths 3 -nosplit > [mq65_rpt ${stage}_setup_ss.rpt]
    report_timing -scenarios func_ff -delay_type min -max_paths 3 -nosplit > [mq65_rpt ${stage}_hold_ff.rpt]
    report_utilization                               > [mq65_rpt ${stage}_util.rpt]
    report_constraints -all_violators -max_transition -max_capacitance -nosplit > [mq65_rpt ${stage}_drv.rpt]
}

# mq65.sdc reads the output load from a library pin; ICC2 has no load_of
if {[info commands load_of] eq ""} {
    proc load_of {pin} { return [lindex [get_attribute [get_lib_pins */[join [lrange [split $pin /] end-1 end] /]] pin_capacitance] 0] }
}
