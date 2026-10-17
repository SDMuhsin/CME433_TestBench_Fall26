# Load a gan65 DC netlist into PrimeTime / PrimePower at one library corner (pre-layout,
# ideal clocks): the same constraints DC compiled against (src_int8_tsmc65 mq65.sdc) and
# the DC estimated parasitics.
#   gan65_pt_load <syn_dir> <corner> <rc> <period>
#     rc: max | min (DC topographical SPEF) | none
source $::env(GAN65)/syn/common/flow.tcl

proc gan65_pt_load {syn_dir corner rc period} {
    set_app_var search_path [list . $::MQ65_LIBDIR]
    set_app_var link_path [list * [mq65_db $corner]]
    read_verilog $syn_dir/gan65_chip.v
    current_design gan65_chip
    link_design gan65_chip
    set ::mq_period $period
    set ::mq_lib [mq65_lib $corner]
    set_operating_conditions [mq65_oc $corner] -library [mq65_lib $corner]
    source $::env(MQ65)/syn/constraints/mq65.sdc
    if {$rc ne "none"} { read_parasitics -format spef $syn_dir/gan65_chip.$rc.spef }
}
