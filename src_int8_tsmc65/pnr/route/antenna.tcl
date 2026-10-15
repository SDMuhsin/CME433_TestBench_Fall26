# Load the kit's antenna rules. The file is written for the older Milkyway-based tool: its
# rule commands take the library as a first argument, which ICC2 does not, and it sets a
# router parameter that does not exist here. Both are stripped before the rules are applied.
set f [open $::MQ65_ANT_RULES r]; set rules [read $f]; close $f
regsub -all -line {^\s*set_parameter .*$} $rules {} rules
regsub -all -line {^\s*set lib .*$} $rules {} rules
regsub -all {\$lib\M;?} $rules {} rules
uplevel #0 $rules
report_antenna_rules > [mq65_rpt route_antenna_rules.rpt]
