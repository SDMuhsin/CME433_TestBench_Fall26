# Compact summary writers (summary numbers + instance names only; safe to copy off the server).
# Shared by DC (dc_syn.tcl) and PrimeTime (pt_sta.tcl).

# key hierarchies: label instance
set ::MQ65_HIER {
    host      u_host
    csr       u_csr
    core      u_core
    fifo      u_core/u_fifo
    seq       u_core/u_seq
    ucode_rom u_core/u_seq/u_rom
    dp        u_core/u_dp
    mul24x17  u_core/u_dp/u_mul
    lane      u_core/u_dp/u_lane
    wb        u_core/u_dp/u_wb
    nlu       u_core/u_nlu
    nlu_rom   u_core/u_nlu/u_rom
    arb       u_core/u_arb
    mem       u_core/u_mem
    hmem      u_core/u_mem/u_h
    bmem      u_core/u_mem/u_b
}

proc mq65_leaf {pattern} {
    return [get_cells -quiet -hierarchical -filter "is_hierarchical==false && full_name=~$pattern"]
}
proc mq65_area {cells} {
    set a 0.0
    foreach_in_collection c $cells { set a [expr {$a + [get_attribute -quiet $c area]}] }
    return $a
}
proc mq65_count {cells} { return [sizeof_collection $cells] }

# worst slack / TNS / endpoint violations of one delay type
proc mq65_slack {type} {
    set p [get_timing_paths -delay_type $type -max_paths 1]
    set wns [get_attribute $p slack]
    set sp [get_object_name [get_attribute $p startpoint]]
    set ep [get_object_name [get_attribute $p endpoint]]
    set tns 0.0; set nv 0
    foreach_in_collection q [get_timing_paths -delay_type $type -max_paths 100000 \
                               -nworst 1 -slack_lesser_than 0.0] {
        set tns [expr {$tns + [get_attribute $q slack]}]; incr nv
    }
    return [list $wns $tns $nv $sp $ep [get_attribute $p arrival]]
}

proc mq65_put_timing {fh} {
    foreach t {max min} {
        lassign [mq65_slack $t] wns tns nv sp ep arr
        set nm [expr {$t eq "max" ? "setup" : "hold"}]
        puts $fh [format "%-6s WNS %8.3f ns  TNS %9.3f ns  violating_endpoints %d" $nm $wns $tns $nv]
        puts $fh "       worst path: $sp -> $ep (arrival [format %.3f $arr] ns)"
    }
}

proc mq65_put_area {fh} {
    set nand2 [get_attribute [get_lib_cells */$::MQ65_NAND2] area]
    set all   [mq65_leaf *]
    set seq_f [get_cells -quiet -hierarchical -filter "is_hierarchical==false && is_sequential==true && is_positive_level_sensitive!=true && is_negative_level_sensitive!=true && is_integrated_clock_gating_cell!=true"]
    set lat   [all_registers -level_sensitive]
    set icg   [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~$::MQ65_ICG_PATTERN"]
    set icg_rf [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~$::MQ65_ICG_PATTERN && full_name=~*u_rf/GEN_W*"]
    set rf    [mq65_leaf *u_sram/u_rf/*]
    set a_all [mq65_area $all]
    puts $fh [format "total_cell_area_um2 %.1f" $a_all]
    puts $fh [format "nand2_ref %s area_um2 %.3f" $::MQ65_NAND2 $nand2]
    puts $fh [format "gate_equivalents %.0f" [expr {$a_all / $nand2}]]
    puts $fh [format "leaf_cells %d" [mq65_count $all]]
    puts $fh [format "flops %d area %.1f" [mq65_count $seq_f] [mq65_area $seq_f]]
    puts $fh [format "latches %d area %.1f" [mq65_count $lat] [mq65_area $lat]]
    puts $fh [format "icg_cells %d (rf_word_gates %d) area %.1f" [mq65_count $icg] [mq65_count $icg_rf] [mq65_area $icg]]
    set rf_lat [get_cells -quiet -hierarchical -filter "is_hierarchical==false && full_name=~*u_sram/u_rf/* && (is_positive_level_sensitive==true || is_negative_level_sensitive==true)"]
    set rf_seq [get_cells -quiet -hierarchical -filter "is_hierarchical==false && full_name=~*u_sram/u_rf/* && is_sequential==true"]
    set a_rf [mq65_area $rf]
    puts $fh [format "rf_total (11 x 256x8) cells %d area %.1f (%.1f %%)" [mq65_count $rf] $a_rf [expr {100.0*$a_rf/$a_all}]]
    puts $fh [format "rf_latches area %.1f" [mq65_area $rf_lat]]
    puts $fh [format "rf_icg area %.1f" [mq65_area $icg_rf]]
    puts $fh [format "rf_seq_all (latches+flops+icg) area %.1f" [mq65_area $rf_seq]]
    puts $fh [format "logic_outside_rf area %.1f" [expr {$a_all - $a_rf}]]
    puts $fh "hierarchy (leaf-cell area um2, cells):"
    foreach {lbl inst} $::MQ65_HIER {
        set c [mq65_leaf $inst/*]
        puts $fh [format "  %-10s %-24s %12.1f %8d" $lbl $inst [mq65_area $c] [mq65_count $c]]
    }
    set top [remove_from_collection $all [mq65_leaf */*]]
    puts $fh [format "  %-10s %-24s %12.1f %8d" top_glue (top) [mq65_area $top] [mq65_count $top]]
}

proc mq65_summary {path period topo} {
    set fh [open $path w]
    puts $fh "mq_chip 65 nm DC summary"
    puts $fh "period_ns $period  mode [expr {$topo ? {topographical} : {wire-load}}]  corner $::MQ65_CORNER_DESC"
    mq65_put_area $fh
    mq65_put_timing $fh
    close $fh
}
