# Read-only per-instance power dump (OpenSTA). Env: RUN CORNER SAIF OUT TAG SCOPE FLOWCOMMON (sta_corner.tcl dir).
# Reuses the flow's sta_corner.tcl (libs, netlist, signoff SDC, SPEF) and the existing SAIF.
set out $::env(OUT); set tag $::env(TAG)
source $::env(FLOWCOMMON)/sta_corner.tcl
read_saif -scope $::env(SCOPE) $::env(SAIF)
report_power -corner $::corner -digits 9 -instances [get_cells *] > $out/power_inst.$tag.rpt
puts "wrote $out/power_inst.$tag.rpt"
