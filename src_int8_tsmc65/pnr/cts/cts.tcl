# Stage 3: clock tree synthesis, clock routing and post-CTS optimisation (setup at ss,
# hold at ff), clocks propagated from here on.
#   clock nets: double-spacing rule on M3-M6, CTS cells from site config (MQ65_CTS_CELLS)
source $::env(MQ65)/syn/common/pnr_common.tcl
mq65_open_stage place cts
create_routing_rule mq_ck_2s -multiplier_spacing 2
set_clock_routing_rules -rules mq_ck_2s -min_routing_layer M3 -max_routing_layer M6
set_clock_tree_options -target_skew 0.10
set_app_options -name clock_opt.hold.effort -value high
clock_opt
report_clock_qor                       > [mq65_rpt cts_clock_qor.rpt]
report_clock_qor -type latency         > [mq65_rpt cts_clock_latency.rpt]
mq65_stage_reports cts
mq65_save_stage cts
puts "STAGE_OK cts"
exit
