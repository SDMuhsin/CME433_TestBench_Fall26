# Stage 2: timing-driven placement and pre-CTS optimisation (ideal clocks).
source $::env(MQ65)/syn/common/pnr_common.tcl
mq65_open_stage floorplan
set_app_options -name place.coarse.continue_on_missing_scandef -value true
set_app_options -name opt.tie_cell.max_fanout -value 8
place_opt
check_legality > [mq65_rpt place_legality.rpt]
report_congestion > [mq65_rpt place_congestion.rpt]
mq65_stage_reports place
mq65_save_stage place
puts "STAGE_OK place"
exit
