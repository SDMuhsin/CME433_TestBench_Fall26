# Summary writers for the power run (numbers and instance names only; safe to copy off the server).

# SAIF window length from the file header (DURATION in TIMESCALE units)
proc mq65_put_saif_window {fh saif} {
    set f [open $saif r]; set head [read $f 4096]; close $f
    regexp {\(TIMESCALE\s+([0-9]+)\s*(\w+)\)} $head -> tsn tsu
    regexp {\(DURATION\s+([0-9.eE+]+)\)} $head -> dur
    set scale [dict get {fs 1e-15 ps 1e-12 ns 1e-9 us 1e-6} $tsu]
    puts $fh [format "saif_window_s %.6e  (%s x %s %s)" [expr {$dur * $tsn * $scale}] $dur $tsn $tsu]
}

# SAIF annotation (read_saif summary) and the report_switching_activity table
proc mq65_put_coverage {fh saif_rpt sw_rpt} {
    puts $fh "switching activity annotation:"
    set f [open $saif_rpt r]
    foreach line [split [read $f] "\n"] { if {[regexp {^(Total|Number)} $line]} { puts $fh "  saif: $line" } }
    close $f
    set f [open $sw_rpt r]
    foreach line [split [read $f] "\n"] { if {[string first "|" $line] >= 0 || [regexp {%} $line]} { puts $fh "  $line" } }
    close $f
}

# design totals (W) and the power-group table of report_power
proc mq65_put_power {fh rpt} {
    set d [current_design]
    foreach a {internal_power switching_power leakage_power total_power} {
        puts $fh [format "%-16s %.6e W" $a [get_attribute $d $a]]
    }
    puts $fh "power groups:"
    set f [open $rpt r]
    foreach line [split [read $f] "\n"] {
        if {[regexp {^\s*(clock_network|register|combinational|sequential|memory|io_pad|black_box|Net Switching|Cell Internal|Cell Leakage|Total Power|Intrinsic|Glitch|X-tran)} $line]} { puts $fh "  $line" }
    }
    close $f
}

# total power of the key hierarchies (same list as the DC area summary)
proc mq65_put_hier_power {fh} {
    source $::env(MQ65)/syn/common/summary.tcl
    puts $fh "hierarchy total power (W):"
    foreach {lbl inst} $::MQ65_HIER {
        set c [get_cells -quiet $inst]
        if {[sizeof_collection $c] == 0} { continue }
        set p [get_attribute -quiet $c total_power]
        puts $fh [format "  %-10s %-24s %s" $lbl $inst $p]
    }
}

# root clock net (driven by the clk port; no clock tree before CTS): load and activity, and
# its switching power 0.5 C V^2 TR, which is not attributed to any driving cell
proc mq65_put_clock_net {fh} {
    set n [get_nets clk]
    set c [get_attribute $n total_capacitance_max]
    set tr [get_attribute $n toggle_rate]
    set v [get_attribute -quiet [index_collection [get_libs] 0] nom_voltage]
    set loads [sizeof_collection [get_pins -quiet -of_objects $n -leaf -filter "direction==in"]]
    puts $fh [format "clock_root_net loads %d  cap %.4f pF  toggle_rate %s /ns  reported switching %s W" \
        $loads $c $tr [get_attribute -quiet $n switching_power]]
    if {$v ne "" && $tr ne ""} {
        puts $fh [format "clock_root_net 0.5*C*V^2*TR = %.4e W (V = %s)" [expr {0.5 * $c * 1e-12 * $v * $v * $tr * 1e9}] $v]
    }
}
