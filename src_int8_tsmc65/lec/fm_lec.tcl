# Formality: RTL (reference) vs DC netlist (implementation) with the DC guidance file.
# Environment (set by lec/run_fm.csh): MQ65 MQ65_SYN (DC output dir) MQ65_CORNER MQ65_OUT MQ65_TAG
# Post-layout check (MQ65_FM_IMPL set): DC netlist (reference) vs the routed netlist
# MQ65_FM_IMPL, with the guidance files written by the place-and-route stages.
# Reference = the RTL DC read (rtl_mem/chip65.f, site ICG wrapper); both containers link the
# DC target library of that run.
source $::env(MQ65)/syn/common/libs.tcl
source $::env(MQ65)/syn/common/rtl.tcl
set syn $::env(MQ65_SYN)
set out $::env(MQ65_OUT)
file mkdir $out/rpt
set_host_options -max_cores 8

set_app_var synopsys_auto_setup true
# DC -gate_clock inserted latch-based integrated clock gates that are not in the RTL
set_app_var verification_clock_gate_hold_mode any
set post [info exists ::env(MQ65_FM_IMPL)]
if {!$post} { set_svf $syn/mq_chip.svf }
# routed netlist: guidance recorded by the place-and-route stages (pnr_common.tcl), in order
if {$post} {
    set svfs {}
    foreach s {place cts route finish} {
        set f [file dirname [file dirname $::env(MQ65_FM_IMPL)]]/svf/$s.svf
        if {[file exists $f]} { lappend svfs $f }
    }
    if {[llength $svfs]} { set_svf -ordered {*}$svfs }
    # No merge, black-box or don't-verify settings: placement keeps every clock gate
    # (pnr/place/place.tcl), so all state points match one to one.
}

read_db -technology_library [mq65_db $::env(MQ65_CORNER)]
set_app_var search_path [concat . [mq65_rtl_incdirs]]
if {$post} {
    read_verilog -container r -libname WORK -05 $syn/mq_chip.v
    set impl_net $::env(MQ65_FM_IMPL)
} else {
    read_verilog -container r -libname WORK -05 [mq65_rtl_files]
    set impl_net $syn/mq_chip.v
}
set_top r:/WORK/mq_chip
read_verilog -container i -libname WORK -05 $impl_net
set_top i:/WORK/mq_chip

match
report_unmatched_points                  > $out/rpt/unmatched.rpt
set_app_var verification_failing_point_limit 0
set ok [verify]
report_status                            > $out/rpt/status.rpt
report_failing_points                    > $out/rpt/failing.rpt
report_aborted_points                    > $out/rpt/aborted.rpt
report_unverified_points                 > $out/rpt/unverified.rpt
report_guidance -summary                 > $out/rpt/guidance.rpt
if {!$ok} { analyze_points -failing      > $out/rpt/analyze.rpt }

set fh [open $out/summary.txt w]
puts $fh "mq_chip 65 nm Formality summary ($::env(MQ65_TAG))"
puts $fh "netlist [file tail $syn][expr {$post ? { vs routed netlist} : {}}]  library corner $::env(MQ65_CORNER)  verify_return $ok"
set fs [open $out/rpt/status.rpt r]
foreach line [split [read $fs] "\n"] {
    if {[regexp {(Verification|Passing|Failing|Aborted|Unverified|Not Compared|Unread|Unmatched|Matched|Compare Points|BBPin)} $line]} { puts $fh "  $line" }
}
close $fs
puts $fh "unmatched (after match, before verify):"
set fu [open $out/rpt/unmatched.rpt r]
set types {}
foreach line [split [read $fu] "\n"] {
    if {[regexp {^\s*[0-9]+ Unmatched} $line]} { puts $fh "  $line" }
    if {[regexp {^\s+(Ref|Impl)\s+(\S+)\s} $line -> side ty]} { dict incr types "$side $ty" }
}
close $fu
dict for {k n} $types { puts $fh "    $k: $n" }
set fg [open $out/rpt/guidance.rpt r]
foreach line [split [read $fg] "\n"] { if {[regexp {^Total\s} $line]} { puts $fh "guidance (accepted rejected unsupported unprocessed total) $line" } }
close $fg
close $fh
exit
