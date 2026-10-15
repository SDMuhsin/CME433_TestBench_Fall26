# OpenSTA: signoff STA of one corner of the routed mb_chip + SDF for the timing GLS.
#   sta -no_splash -exit write_sdf.tcl      with env:
#     RUN     run dir (final/nl, final/spef, resolved.json inputs)
#     CORNER  e.g. min_ff_n40C_3v60 / nom_tt_025C_3v30 / max_ss_125C_3v00
#     OUT     output dir: <OUT>/mb_chip.<CORNER>.sdf, <OUT>/sta.<CORNER>.rpt
#     CLOCK_PERIOD_OVERRIDE  optional period (ns) for a negative-test STA
# Corner setup (Liberty, netlist, SDC, SPEF): src/flow/common/sta_corner.tcl.  SDF = OpenSTA
# write_sdf -include_typ -divider . (as LibreLane), i.e. min:typ:max per value.
set out $::env(OUT)
source [file join [file dirname [file dirname [file dirname [file normalize [info script]]]]] common sta_corner.tcl]
set corner $::corner

set rpt [open $out/sta.$corner.rpt w]
puts $rpt "corner $corner  rc $::rc  pvt $::pvt  period $::env(CLOCK_PERIOD) ns"
foreach l $::libs { puts $rpt "lib $l" }
puts $rpt "spef $::spef"
close $rpt
report_worst_slack -max -digits 4 >> $out/sta.$corner.rpt
report_worst_slack -min -digits 4 >> $out/sta.$corner.rpt
report_tns -max -digits 4 >> $out/sta.$corner.rpt
report_tns -min -digits 4 >> $out/sta.$corner.rpt
report_checks -path_delay min -group_path_count 5 -format end > $out/hold_end.$corner.rpt
report_checks -path_delay max -group_path_count 5 -format end > $out/setup_end.$corner.rpt
report_checks -path_delay min -group_path_count 200 -endpoint_path_count 1 -fields {slew cap} \
    -format full_clock_expanded > $out/hold_paths.$corner.rpt
report_annotated_delay > $out/annotated.$corner.rpt
# timing-arc order per cell type (= the order of write_sdf IOPATHs; sdf/fix_sdf.py uses it to tell
# the positive- from the negative-unate IOPATH of xor/xnor/mux2 pin pairs)
set arcs [open $out/arcs.$corner.rpt w]
array set seen {}
foreach inst [get_cells *] {
    set ref [get_property $inst ref_name]
    if {[info exists seen($ref)]} continue
    set seen($ref) 1
    set ins {}; set outs {}
    foreach p [get_pins -of_objects $inst] {
        set d [get_property $p direction]
        if {$d eq "input"} { lappend ins $p } elseif {$d eq "output"} { lappend outs $p }
    }
    foreach o $outs {
        foreach i $ins {
            sta::redirect_string_begin
            set bad [catch {report_dcalc -from $i -to $o -digits 4}]
            set r [sta::redirect_string_end]
            if {$bad} continue
            if {$r eq ""} continue
            set senses {}
            foreach line [split $r "\n"] {
                if {[regexp {^Arc sense: (\S+)} $line -> sn]} { lappend senses $sn }
            }
            puts $arcs "$ref [get_property $i lib_pin_name] [get_property $o lib_pin_name] $senses"
        }
    }
}
close $arcs
write_sdf -include_typ -divider . -corner $corner $out/mb_chip.$corner.sdf
puts "wrote $out/mb_chip.$corner.sdf"
