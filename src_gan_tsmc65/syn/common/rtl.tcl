# RTL sources of gan65_chip for synthesis and Formality, from rtl/gan65.f:
#   * mem/gan65_icg.v (behavioural)  -> site/gan65_icg_site.v (library ICG) when present
#   * pe/gan_mul8.v (exact)          -> the files listed in $GAN65_MUL_F (one path per line,
#                                       written by syn/scripts/run_dc.csh from bench/variant.py)
proc gan65_rtl_dir {} { return $::env(GAN65)/rtl }
proc gan65_icg_rtl {} {
    set f $::env(GAN65)/site/gan65_icg_site.v
    if {[file exists $f]} { return $f }
    return [gan65_rtl_dir]/mem/gan65_icg.v
}
proc gan65_mul_files {} {
    if {![info exists ::env(GAN65_MUL_F)]} { return [list [gan65_rtl_dir]/pe/gan_mul8.v] }
    set fh [open $::env(GAN65_MUL_F) r]
    set files {}
    foreach line [split [read $fh] "\n"] {
        if {[string trim $line] ne ""} { lappend files [string trim $line] }
    }
    close $fh
    return $files
}
proc gan65_rtl_files {} {
    set fh [open [gan65_rtl_dir]/gan65.f r]
    set files {}
    foreach line [split [read $fh] "\n"] {
        set line [string trim $line]
        if {$line eq "" || [string match "//*" $line]} { continue }
        switch -- $line {
            mem/gan65_icg.v { lappend files [gan65_icg_rtl] }
            pe/gan_mul8.v   { lappend files {*}[gan65_mul_files] }
            default         { lappend files [gan65_rtl_dir]/$line }
        }
    }
    close $fh
    return $files
}
proc gan65_rtl_incdirs {} { return [list [gan65_rtl_dir]/seq] }
