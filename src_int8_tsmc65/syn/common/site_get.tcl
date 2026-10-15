# Print site config values for shell scripts:  tclsh syn/common/site_get.tcl <VAR> ...
#   e.g. tclsh $MQ65/syn/common/site_get.tcl MQ65_DRC_DECK   (MQ65 and MQ65_KIT must be set)
source $::env(MQ65)/site/site.tcl
foreach v $argv { puts [set ::$v] }
