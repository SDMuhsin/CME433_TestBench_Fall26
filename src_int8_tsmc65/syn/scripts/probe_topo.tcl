# Probe: can DC topographical mode use the kit's Milkyway reference library?
source $::env(MQ65)/syn/common/libs.tcl
set_app_var target_library [mq65_db tt]
set_app_var link_library "* $target_library"
file delete -force probe_mw
set rc [catch {create_mw_lib -technology $::MQ65_TF -mw_reference_library $::MQ65_MW_REF probe_mw} msg]
puts "PROBE create_mw_lib rc=$rc $msg"
set rc [catch {open_mw_lib probe_mw} msg]
puts "PROBE open_mw_lib rc=$rc $msg"
set rc [catch {mq65_rc_setup} msg]
puts "PROBE tlu rc=$rc $msg"
exit
