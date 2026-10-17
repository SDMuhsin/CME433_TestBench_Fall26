# Compact Formality summary (status counts, unmatched point types, SVF guidance) from the
# reports fm_lec.tcl wrote to <out>/rpt.
proc gan65_fm_lines {path re} {
    set fh [open $path r]
    set l [lsearch -all -inline -regexp [split [read $fh] "\n"] $re]
    close $fh
    return $l
}
proc gan65_fm_summary {out syn ok} {
    set fh [open $out/summary.txt w]
    puts $fh "gan65_chip 65 nm Formality summary ($::env(GAN65_TAG))"
    puts $fh "netlist [file tail $syn]  library corner $::env(GAN65_CORNER)  verify_return $ok"
    foreach l [gan65_fm_lines $out/rpt/status.rpt {(Verification|Passing|Failing|Aborted|Unverified|Not Compared|Unread|Unmatched|Matched|Compare Points|BBPin)}] {
        puts $fh "  $l"
    }
    puts $fh "unmatched (after match, before verify):"
    set types {}
    foreach l [gan65_fm_lines $out/rpt/unmatched.rpt {^\s*([0-9]+ Unmatched|(Ref|Impl)\s)}] {
        if {[regexp {^\s+(Ref|Impl)\s+(\S+)\s} $l -> side ty]} { dict incr types "$side $ty" } else { puts $fh "  $l" }
    }
    dict for {k n} $types { puts $fh "    $k: $n" }
    foreach l [gan65_fm_lines $out/rpt/guidance.rpt {^Total\s}] {
        puts $fh "guidance (accepted rejected unsupported unprocessed total) $l"
    }
    close $fh
}
