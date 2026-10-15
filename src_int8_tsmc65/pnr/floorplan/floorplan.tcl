# Stage 1: design import, MCMM setup and floorplan (core-only block, no pad ring).
# Square core at the target utilisation (MQ65_UTIL), core offset leaves room for the
# power ring, signal pins on the block boundary (pnr/floorplan/pins.tcl).
source $::env(MQ65)/syn/common/pnr_common.tcl
mq65_host
create_lib [mq65_lib_path] -technology $::MQ65_TF -ref_libs [list [mq65_ndm]]
read_verilog -top mq_chip $::env(MQ65_SYN)/mq_chip.v
current_block mq_chip
link_block
save_block -as mq_chip/init
current_block mq_chip/init
mq65_scenarios
mq65_cell_usage
initialize_floorplan -core_utilization $::env(MQ65_UTIL) -side_ratio {1 1} \
    -core_offset {12 12 12 12} -site_def $::MQ65_SITE -flip_first_row true
source $::env(MQ65)/pnr/floorplan/pins.tcl
source $::env(MQ65)/pnr/floorplan/pg.tcl
report_design -floorplan > [mq65_rpt floorplan_design.rpt]
check_pg_connectivity     > [mq65_rpt floorplan_pg_conn.rpt]
check_pg_drc              > [mq65_rpt floorplan_pg_drc.rpt]
save_block -as mq_chip/floorplan
puts "STAGE_OK floorplan"
exit
