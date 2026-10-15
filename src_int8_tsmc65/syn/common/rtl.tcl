# RTL sources of mq_chip for the 65 nm flow, from rtl/mem/chip65.f on the server tree:
#   core/... -> $MQ65/rtl/core (src_int8/rtl, unchanged)   mem/... -> $MQ65/rtl/mem (rtl_mem)
proc mq65_rtl_files {} {
    set root $::env(MQ65)/rtl
    set fh [open $root/mem/chip65.f r]
    set files {}
    foreach line [split [read $fh] "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "//*" $line]} { continue }
        # site-specific ICG wrapper (library cell) replaces the behavioural model
        if {$line eq "mem/mq65_icg.v" && [info exists ::MQ65_ICG_RTL] && $::MQ65_ICG_RTL ne ""} {
            lappend files $::MQ65_ICG_RTL; continue
        }
        lappend files $root/$line
    }
    close $fh
    return $files
}
proc mq65_rtl_incdirs {} {
    return [list $::env(MQ65)/rtl/core/nonlin $::env(MQ65)/rtl/core/seq]
}
