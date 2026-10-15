# Power grid: core ring and a coarse mesh on the two top metals, cell rails on M1,
# via stacks from the mesh down to the rails.
#   ring  : top two layers, 3 um wide
#   mesh  : top two layers, 2 um straps, VDD/VSS interleaved, 40 um pitch
#   rails : standard-cell power rails (cell row pins)
lassign $::MQ65_PG vdd vss
create_net -power $vdd
create_net -ground $vss
connect_pg_net -automatic
lassign $::MQ65_PG_LAYERS rail_l v_l h_l
create_pg_ring_pattern mq_ring -horizontal_layer $h_l -horizontal_width 3 -horizontal_spacing 1.5 \
    -vertical_layer $v_l -vertical_width 3 -vertical_spacing 1.5
set_pg_strategy mq_ring -core -pattern {{name: mq_ring} {nets: {VDD VSS}} {offset: {2 2}}}
create_pg_mesh_pattern mq_mesh -layers [list \
    [list [list vertical_layer: $v_l]   {width: 2} {spacing: interleaving} {pitch: 40} {offset: 10}] \
    [list [list horizontal_layer: $h_l] {width: 2} {spacing: interleaving} {pitch: 40} {offset: 10}]]
set_pg_strategy mq_mesh -core -pattern {{name: mq_mesh} {nets: {VDD VSS}}} -extension {{stop: outermost_ring}}
create_pg_std_cell_conn_pattern mq_rails -layers [list $rail_l]
set_pg_strategy mq_rails -core -pattern {{name: mq_rails} {nets: {VDD VSS}}}
compile_pg -strategies {mq_ring mq_mesh mq_rails}
