# Stage 2: timing-driven placement and pre-CTS optimisation (ideal clocks).
source $::env(MQ65)/syn/common/pnr_common.tcl
mq65_open_stage floorplan place
set_app_options -name place.coarse.continue_on_missing_scandef -value true
set_app_options -name opt.tie_cell.max_fanout -value 8
# Keep every synthesised clock gate: merging equivalent gates across hierarchy (e.g. the word
# gates of parallel byte register files) leaves guidance that equivalence checking cannot
# apply, so the routed netlist would not be provably equivalent to the synthesis netlist.
set_app_options -name place_opt.flow.merge_clock_gates -value false
place_opt
check_legality > [mq65_rpt place_legality.rpt]
report_congestion > [mq65_rpt place_congestion.rpt]
mq65_stage_reports place
mq65_save_stage place
puts "STAGE_OK place"
exit
