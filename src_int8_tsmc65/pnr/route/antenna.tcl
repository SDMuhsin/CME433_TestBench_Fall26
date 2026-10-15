# Load the kit's antenna rules (written for the older Milkyway-based tool): the few
# commands that do not exist in ICC2 are mapped to their ICC2 equivalents or ignored.
proc set_parameter {args} {}
if {[info commands current_mw_lib] eq ""} { proc current_mw_lib {} { return [current_lib] } }
if {[info commands remove_antenna_rules] eq ""} { proc remove_antenna_rules {args} {} }
source $::MQ65_ANT_RULES
report_antenna_rules > [mq65_rpt route_antenna_rules.rpt]
