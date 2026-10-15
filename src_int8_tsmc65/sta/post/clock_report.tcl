# Clock tree digest for the post-layout summary: sink latency range (global skew) and
# the cell count of the clock network (numbers only).
proc mq65_put_clock_tree {fh} {
    set sinks [get_pins -quiet -hierarchical -filter "is_clock_pin==true && direction==in"]
    set lmin 1e9; set lmax -1e9; set n 0
    foreach_in_collection p $sinks {
        set a [get_attribute -quiet $p max_rise_arrival]
        if {$a eq "" || $a eq "INFINITY"} { continue }
        incr n
        if {$a < $lmin} { set lmin $a }
        if {$a > $lmax} { set lmax $a }
    }
    puts $fh [format "clock sinks %d (timed %d)  latency_ns min %.3f max %.3f  global_skew_ns %.3f" \
        [sizeof_collection $sinks] $n $lmin $lmax [expr {$lmax - $lmin}]]
    if {[catch {
        set cn [get_clock_network_objects -type cell [get_clocks clk]]
        set icg [sizeof_collection [filter_collection $cn "is_integrated_clock_gating_cell==true"]]
        set buf [sizeof_collection [filter_collection $cn "is_combinational==true && number_of_pins==2"]]
        puts $fh [format "clock network cells %d (buffers/inverters %d, clock gates %d)" \
            [sizeof_collection $cn] $buf $icg]
    } err]} { puts $fh "clock network cells: n/a ($err)" }
}
