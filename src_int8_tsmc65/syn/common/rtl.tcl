# RTL sources of mq_chip for the 65 nm flow, from rtl_mem/chip65.f in the repository clone:
#   core/... -> <repo>/src_int8/rtl (unchanged)   mem/... -> $MQ65/rtl_mem
proc mq65_core_dir {} { return [file dirname $::env(MQ65)]/src_int8/rtl }
proc mq65_rtl_files {} {
    set fh [open $::env(MQ65)/rtl_mem/chip65.f r]
    set files {}
    foreach line [split [read $fh] "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "//*" $line]} { continue }
        # site-specific ICG wrapper (library cell) replaces the behavioural model
        if {$line eq "mem/mq65_icg.v" && [info exists ::MQ65_ICG_RTL] && $::MQ65_ICG_RTL ne ""} {
            lappend files $::MQ65_ICG_RTL; continue
        }
        regsub {^core/} $line [mq65_core_dir]/ line
        regsub {^mem/} $line $::env(MQ65)/rtl_mem/ line
        lappend files $line
    }
    close $fh
    return $files
}
proc mq65_rtl_incdirs {} {
    return [list [mq65_core_dir]/nonlin [mq65_core_dir]/seq]
}
