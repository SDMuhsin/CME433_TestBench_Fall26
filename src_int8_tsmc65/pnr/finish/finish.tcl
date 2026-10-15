# Stage 5: filler insertion, final checks and output views.
#   checks : check_routes, check_lvs (ICC2 connectivity vs netlist), check_pg_connectivity
#   outputs: pnr/finish/write_out.tcl
source $::env(MQ65)/syn/common/pnr_common.tcl
mq65_open_stage route
set fill {}
foreach p $::MQ65_FILLERS { append_to_collection fill [get_lib_cells */$p] }
create_stdcell_fillers -lib_cells $fill
connect_pg_net -automatic
remove_stdcell_fillers_with_violation
check_legality                     > [mq65_rpt finish_legality.rpt]
check_routes                       > [mq65_rpt finish_check_routes.rpt]
check_lvs -max_errors 0            > [mq65_rpt finish_check_lvs.rpt]
check_pg_connectivity              > [mq65_rpt finish_pg_conn.rpt]
check_pg_drc                       > [mq65_rpt finish_pg_drc.rpt]
mq65_stage_reports finish
report_clock_qor                   > [mq65_rpt finish_clock_qor.rpt]
mq65_save_stage finish
source $::env(MQ65)/pnr/finish/write_out.tcl
source $::env(MQ65)/pnr/finish/summary.tcl
puts "STAGE_OK finish"
exit
