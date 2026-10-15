# OpenSTA power of the routed mb_chip at one corner, with simulation activity (VCD) or vectorless.
#   sta -no_splash -exit power.tcl      with env:
#     RUN     run dir (final/nl, final/spef)
#     CORNER  e.g. nom_tt_025C_3v30 (setup: src/flow/common/sta_corner.tcl, as the SDF GLS STA)
#     OUT     output dir; reports power.<TAG>.rpt, activity.<TAG>.rpt
#     TAG     report name suffix
#     SAIF    optional: per-pin SAIF from activity/vcd2saif.py (the SDF GLS net VCD of one token);
#             without it: vectorless (OpenSTA default input activity, as the LibreLane signoff)
#     SCOPE   SAIF scope of the design, default tb_mb_chip_sdf/dut
#     PROXY_LIB optional: report/proxy_lib.py flop library; the flops are replace_cell'ed onto it
#             (estimate of the flop internal power + leakage the AS Liberty lacks)
set out $::env(OUT)
set tag $::env(TAG)
set proxy [expr {[info exists ::env(PROXY_LIB)] && $::env(PROXY_LIB) ne ""}]
if {$proxy} { set ::mb_extra_libs [list $::env(PROXY_LIB)] }
source [file join [file dirname [file dirname [file dirname [file normalize [info script]]]]] common sta_corner.tcl]
set corner $::corner
set flops {}
foreach ref {dfxtp_2 dfxtp_4 dfsrtp_2} {
    foreach c [get_cells -quiet -filter "ref_name == gf180mcu_as_sc_mcu7t3v3__$ref" *] { lappend flops $c }
}
if {$proxy} {
    # swap the flops onto the proxy library cells (same names/pins, fd_sc 7t5v0 power data)
    foreach c $flops { replace_cell $c mb_flop_power_proxy/[get_property $c ref_name] }
    puts "proxy: [llength $flops] flops now from [get_property [get_lib_cells -of_objects [lindex $flops 0]] library]"
}

set t0 [clock seconds]
if {[info exists ::env(SAIF)] && $::env(SAIF) ne ""} {
    set scope [expr {[info exists ::env(SCOPE)] ? $::env(SCOPE) : "tb_mb_chip_sdf/dut"}]
    read_saif -scope $scope $::env(SAIF)
    puts "read_saif $::env(SAIF) scope $scope in [expr {[clock seconds] - $t0}] s"
}
report_activity_annotation > $out/activity.$tag.rpt
report_activity_annotation -report_unannotated > $out/unannotated.$tag.rpt
report_power -corner $corner -digits 6 > $out/power.$tag.rpt
set srams [get_cells -filter "ref_name == gf180mcu_ocd_ip_sram__sram256x8m8wm1" *]
report_power -corner $corner -digits 6 -instances $srams > $out/power_sram.$tag.rpt
report_power -corner $corner -digits 6 -instances $flops > $out/power_flops.$tag.rpt
puts "power reports -> $out/power.$tag.rpt"
