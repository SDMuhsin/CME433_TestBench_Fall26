# Layout summary of the routed block (numbers only; safe to copy off the server):
# die / core area, utilisation, cell counts, wire length, ICC2 timing per scenario and
# the check results.  Written to $MQ65_PNR/summary.txt.
proc mq65_bbox_area {bb} {
    lassign $bb ll ur
    return [list [expr {[lindex $ur 0] - [lindex $ll 0]}] [expr {[lindex $ur 1] - [lindex $ll 1]}]]
}
proc mq65_grep_rpt {fh path pattern} {
    set f [open $path r]
    foreach line [split [read $f] "\n"] { if {[regexp $pattern $line]} { puts $fh "  [string trim $line]" } }
    close $f
}

set fh [open $::env(MQ65_PNR)/summary.txt w]
puts $fh "mq_chip 65 nm layout summary ([file tail $::env(MQ65_PNR)], core-only block, no pad ring)"
puts $fh "netlist [file tail $::env(MQ65_SYN)]  period_ns $::env(MQ65_PERIOD)  target_util $::env(MQ65_UTIL)"
lassign [mq65_bbox_area [get_attribute [current_block] boundary_bbox]] dw dh
lassign [mq65_bbox_area [get_attribute [get_core_area] bbox]] cw ch
puts $fh [format "die_um %.2f x %.2f  die_area_um2 %.0f" $dw $dh [expr {$dw*$dh}]]
puts $fh [format "core_um %.2f x %.2f  core_area_um2 %.0f" $cw $ch [expr {$cw*$ch}]]

set leaf [get_cells -hierarchical -filter "is_hierarchical==false"]
set fill {}
foreach p $::MQ65_FILLERS { append_to_collection fill [filter_collection $leaf "ref_name==$p"] }
set ant [filter_collection $leaf "ref_name==$::MQ65_ANT_CELL"]
set std [remove_from_collection [remove_from_collection $leaf $fill] $ant]
set a_std 0.0; foreach_in_collection c $std { set a_std [expr {$a_std + [get_attribute $c area]}] }
set a_core [expr {$cw*$ch}]
puts $fh [format "std_cells %d  std_cell_area_um2 %.0f  utilisation %.1f %%" \
    [sizeof_collection $std] $a_std [expr {100.0*$a_std/$a_core}]]
puts $fh [format "filler_cells %d  antenna_diodes %d" [sizeof_collection $fill] [sizeof_collection $ant]]

redirect -variable rd {report_design -routing}
foreach line [split $rd "\n"] {
    if {[regexp -nocase {(total wire length|number of vias|wire length)} $line]} { puts $fh "routing: [string trim $line]" }
}

puts $fh "icc2 timing (TLU+ RC of each corner, propagated clocks):"
foreach {sc t} {func_ss max func_tt max func_ff min} {
    set p [get_timing_paths -scenarios $sc -delay_type $t -max_paths 1]
    set tns 0.0; set nv 0
    foreach_in_collection q [get_timing_paths -scenarios $sc -delay_type $t -max_paths 100000 -slack_lesser_than -0.0005] {
        set tns [expr {$tns + [get_attribute $q slack]}]; incr nv
    }
    puts $fh [format "  %-8s %-5s WNS %8.4f ns  TNS %9.3f ns  violating_paths %d" $sc \
        [expr {$t eq "max" ? "setup" : "hold"}] [get_attribute $p slack] $tns $nv]
}

set r $::env(MQ65_PNR)/rpt
puts $fh "checks:"
mq65_grep_rpt $fh $r/finish_check_routes.rpt {(?i)(total number of drcs|drc|open|antenna).*[0-9]}
mq65_grep_rpt $fh $r/finish_check_lvs.rpt   {(?i)(short|open|floating|total|error)}
mq65_grep_rpt $fh $r/finish_pg_conn.rpt     {(?i)(floating|number of)}
mq65_grep_rpt $fh $r/finish_legality.rpt    {(?i)(violation|illegal|legal)}
close $fh
