# Load a DC netlist into PrimeTime / PrimePower for one library corner (shared by sta/ and power/).
#   mq65_pt_load <syn_dir> <corner> <rc> <period>
#     syn_dir  DC output directory (mq_chip.v, mq_chip.{max,min}.spef)
#     corner   ss | tt | ff: library (and operating condition) for the analysis
#     rc       max | min: which DC estimated parasitics to annotate ("none" = no wire RC)
#     period   clock period (ns) for syn/constraints/mq65.sdc
# Constraints are the same source DC compiled against (mq65.sdc), with the analysis corner's
# library for the driving cells and output load. Clocks stay ideal (pre-layout).
source $::env(MQ65)/syn/common/libs.tcl

proc mq65_pt_load {syn_dir corner rc period} {
    set_app_var search_path [list . $::MQ65_LIBDIR]
    set_app_var link_path [list * [mq65_db $corner]]
    read_verilog $syn_dir/mq_chip.v
    current_design mq_chip
    link_design mq_chip
    set ::mq_period $period
    set ::mq_lib [mq65_lib $corner]
    set_operating_conditions [mq65_oc $corner] -library [mq65_lib $corner]
    source $::env(MQ65)/syn/constraints/mq65.sdc
    if {$rc ne "none"} {
        read_parasitics -format spef $syn_dir/mq_chip.$rc.spef
    }
}
