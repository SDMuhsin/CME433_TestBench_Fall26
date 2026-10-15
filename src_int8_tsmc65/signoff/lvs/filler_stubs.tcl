# Empty subcircuits for the filler cells (no devices; site config MQ65_FILLERS / MQ65_PG):
#   tclsh signoff/lvs/filler_stubs.tcl > fillers.sp
source $::env(MQ65)/site/site.tcl
foreach c $::MQ65_FILLERS { puts ".SUBCKT $c $::MQ65_PG\n.ENDS" }
