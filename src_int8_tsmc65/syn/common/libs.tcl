# Standard-cell library set for the mq65 flow (DC / PT / PrimePower / Formality).
# All kit-specific names and paths come from the git-ignored site config
# ($MQ65/site/site.tcl, template site/site.example.tcl):
#   ss : setup signoff corner (slow, hot)   tt : typical / power corner   ff : hold corner (fast, cold)

source $::env(MQ65)/site/site.tcl

proc mq65_db {corner} { return $::MQ65_LIBDIR/$::MQ65_CORNER_LIB($corner).db }
proc mq65_lib {corner} { return $::MQ65_CORNER_LIB($corner) }
proc mq65_oc {corner} { return $::MQ65_CORNER_OC($corner) }
proc mq65_tlu {corner} { return $::MQ65_TLU/$::MQ65_CORNER_TLU($corner) }
