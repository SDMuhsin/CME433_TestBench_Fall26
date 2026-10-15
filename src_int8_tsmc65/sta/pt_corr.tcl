# DC/PrimeTime correlation probe: worst setup slack into flops of one netlist under
# PrimeTime's CCS (advanced) vs NLDM-style (basic) driver/receiver models, with and without
# the DC estimated parasitics.  Environment as for pt_sta.tcl (run with sta/run_pt.csh ... corr).
source $::env(MQ65)/syn/common/pt_load.tcl
proc mq65_corr_line {lbl} {
    set ends [add_to_collection [all_registers -edge_triggered -data_pins] [all_outputs]]
    set p [get_timing_paths -delay_type max -max_paths 1 -to $ends]
    puts [format "CORR %-28s slack %8.4f arrival %.4f  %s -> %s" $lbl [get_attribute $p slack] \
        [get_attribute $p arrival] [get_object_name [get_attribute $p startpoint]] \
        [get_object_name [get_attribute $p endpoint]]]
}
mq65_pt_load $::env(MQ65_SYN) $::env(MQ65_CORNER) $::env(MQ65_RC) $::env(MQ65_PERIOD)
mq65_corr_line "spef ccs(advanced)"
set_app_var rc_driver_model_mode basic
set_app_var rc_receiver_model_mode basic
mq65_corr_line "spef nldm(basic)"
remove_annotated_parasitics -all
mq65_corr_line "no-rc nldm(basic)"
set_app_var rc_driver_model_mode advanced
set_app_var rc_receiver_model_mode advanced
mq65_corr_line "no-rc ccs(advanced)"
exit
