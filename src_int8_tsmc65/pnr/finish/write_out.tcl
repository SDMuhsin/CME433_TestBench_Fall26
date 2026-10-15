# Output views of the routed block in $MQ65_PNR/out/:
#   mq_chip.v        post-route netlist (no physical-only cells, no PG) for STA / GLS / power / LEC
#   mq_chip.lvs.v    netlist with PG connections, incl. physical-only cells, for LVS
#   mq_chip.def      full DEF (cells, pins, routing) for StarRC
#   mq_chip.gds      stream-out merged with the cell layouts, for DRC / LVS
#   mq_chip_<corner>.spef  ICC2 extraction (TLU+ RC model of each corner)
set o $::env(MQ65_PNR)/out
file mkdir $o
write_verilog -exclude {physical_only_cells leaf_module_declarations pg_objects} $o/mq_chip.v
write_verilog -include {pg_netlist} $o/mq_chip.lvs.v
write_def -version 5.8 -compress none -include_tech_via_definitions $o/mq_chip.def
# layer map: pin / net text of each metal on the verification deck's text layer
set f [open $o/gds_text.map w]
foreach {m t} $::MQ65_GDS_TEXT {
    foreach pur {0 -1 -2 -3 -4} { puts $f "text $m:$pur:*:* $t:0" }
}
close $f
write_gds -design mq_chip -hierarchy all -long_names -keep_data_type -output_pin all -units 1000 \
    -layer_map $o/gds_text.map -merge_files [list $::MQ65_GDS] $o/mq_chip.gds
write_parasitics -format spef -output $o/mq_chip
write_sdc -output $o/mq_chip.sdc
