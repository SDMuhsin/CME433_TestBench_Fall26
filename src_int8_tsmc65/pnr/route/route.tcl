# Stage 4: timing-driven global / track / detail routing with antenna repair (diode
# insertion), then post-route optimisation incl. hold fixing at ff (up to two passes).
source $::env(MQ65)/syn/common/pnr_common.tcl
mq65_open_stage cts
source $::env(MQ65)/pnr/route/antenna.tcl
set_app_options -name route.global.timing_driven -value true
set_app_options -name route.track.timing_driven  -value true
set_app_options -name route.detail.timing_driven -value true
set_app_options -name route.detail.antenna -value true
set_app_options -name route.detail.insert_diodes_during_routing -value true
set_app_options -name route.detail.diode_libcell_names -value [get_object_name [index_collection [get_lib_cells */$::MQ65_ANT_CELL] 0]]
route_auto
route_opt
# a second incremental pass if setup at ss is still negative
if {[get_attribute [get_timing_paths -scenarios func_ss -max_paths 1] slack] < 0} { route_opt }
check_routes > [mq65_rpt route_check_routes.rpt]
mq65_stage_reports route
mq65_save_stage route
puts "STAGE_OK route"
exit
