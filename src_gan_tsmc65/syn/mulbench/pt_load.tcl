# Load a mul_bench DC netlist into PrimeTime / PrimePower at one library corner (pre-layout,
# ideal clock), with the constraints DC compiled against and the DC estimated parasitics.
#   mb_pt_load <syn_dir> <corner> <rc max|min|none> <period>
source $::env(MQ65)/syn/common/libs.tcl
proc mb_pt_load {syn corner rc period} {
    set_app_var search_path [list . $::MQ65_LIBDIR]
    set_app_var link_path [list * [mq65_db $corner]]
    read_verilog $syn/mul_bench.v
    current_design mul_bench
    link_design mul_bench
    set ::mq_period $period
    set ::mq_lib [mq65_lib $corner]
    set_operating_conditions [mq65_oc $corner] -library [mq65_lib $corner]
    source $::env(MQ65)/syn/constraints/mq65.sdc
    if {$rc ne "none"} { read_parasitics -format spef $syn/mul_bench.$rc.spef }
}
