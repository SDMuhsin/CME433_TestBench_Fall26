# gan65 power summary writers (numbers and instance names only; safe to copy off the server).
# Generic writers (SAIF window, annotation, totals, power groups, root clock net) come from
# src_int8_tsmc65/power/power_digest.tcl; this file adds the gan65 block split and energy.

# sum of internal / switching / leakage / total power (W) over hierarchical cells
proc gan65_power_of {cells} {
    set s [dict create internal 0.0 switching 0.0 leakage 0.0 total 0.0]
    foreach_in_collection c $cells {
        foreach {k a} {internal internal_power switching switching_power leakage leakage_power total total_power} {
            set v [get_attribute -quiet $c $a]
            if {$v ne ""} { dict set s $k [expr {[dict get $s $k] + $v}] }
        }
    }
    return $s
}

proc gan65_hier {pattern} {
    return [get_cells -quiet -hierarchical -filter "is_hierarchical==true && full_name=~$pattern"]
}

proc gan65_split_power_line {fh lbl s tot} {
    set dyn [expr {[dict get $s internal] + [dict get $s switching]}]
    puts $fh [format "  %-12s %11.4e %11.4e %11.4e  %5.1f %%" $lbl [dict get $s total] $dyn \
        [dict get $s leakage] [expr {100.0 * [dict get $s total] / $tot}]]
}

# block split: PE array (with the 16 multipliers), multipliers alone, latch RF, rest
proc gan65_put_power_split {fh} {
    set d [current_design]
    set tot [get_attribute $d total_power]
    set all [dict create internal [get_attribute $d internal_power] switching [get_attribute $d switching_power] \
        leakage [get_attribute $d leakage_power] total $tot]
    set pe  [gan65_power_of [get_cells u_dla/u_pe_array]]
    set mul [gan65_power_of [gan65_hier u_dla/u_pe_array/*u_pe/u_mul]]
    set rf  [gan65_power_of [gan65_hier *u_sram/u_rf]]
    set rest [dict create]
    foreach k {internal switching leakage total} {
        dict set rest $k [expr {[dict get $all $k] - [dict get $pe $k] - [dict get $rf $k]}]
    }
    puts $fh "power_split (W: total, dynamic = internal + switching, leakage; % of chip total):"
    gan65_split_power_line $fh chip $all $tot
    gan65_split_power_line $fh pe_array $pe $tot
    gan65_split_power_line $fh mul8_all $mul $tot
    gan65_split_power_line $fh latch_rf $rf $tot
    gan65_split_power_line $fh rest $rest $tot
    puts $fh "hierarchy total power (W):"
    foreach {lbl inst} $::MQ65_HIER {
        set c [get_cells -quiet $inst]
        if {[sizeof_collection $c]} { puts $fh [format "  %-10s %-24s %s" $lbl $inst [get_attribute -quiet $c total_power]] }
    }
}

# energy per image and throughput: average power x image time (clk_per_image x period)
proc gan65_put_energy {fh period_ns clk_per_image} {
    set d [current_design]
    set t [expr {$clk_per_image * $period_ns * 1e-9}]
    set p [get_attribute $d total_power]
    set lk [get_attribute $d leakage_power]
    puts $fh [format "image_time_s %.6e  (%d clk x %s ns)  images_per_s %.2f" $t $clk_per_image $period_ns [expr {1.0 / $t}]]
    puts $fh [format "energy_per_image_uJ %.4f  (dynamic %.4f  leakage %.4f)" \
        [expr {$p * $t * 1e6}] [expr {($p - $lk) * $t * 1e6}] [expr {$lk * $t * 1e6}]]
}

