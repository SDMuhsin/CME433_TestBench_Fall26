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
                               -nworst 1 -slack_lesser_than -0.0005] {
        set tns [expr {$tns + [get_attribute $q slack]}]; incr nv
    }
    return [list $wns $tns $nv $sp $ep [get_attribute $p arrival]]
}

proc mq65_put_timing {fh} {
    foreach t {max min} {
        lassign [mq65_slack $t] wns tns nv sp ep arr
        set nm [expr {$t eq "max" ? "setup" : "hold"}]
        puts $fh [format "%-6s WNS %8.4f ns  TNS %9.3f ns  violating_endpoints %d" $nm $wns $tns $nv]
        puts $fh "       worst path: $sp -> $ep (arrival [format %.3f $arr] ns)"
    }
    # latch endpoints that borrow sit at slack 0; also show the worst path into flops / outputs
    set ends [add_to_collection [all_registers -edge_triggered -data_pins] [all_outputs]]
    set p [get_timing_paths -delay_type max -max_paths 1 -to $ends]
    puts $fh [format "setup_to_flops WNS %8.4f ns  worst path: %s -> %s (arrival %.3f ns)" \
        [get_attribute $p slack] [get_object_name [get_attribute $p startpoint]] \
        [get_object_name [get_attribute $p endpoint]] [get_attribute $p arrival]]
}

proc mq65_put_area {fh} {
    set nand2 [lindex [get_attribute [get_lib_cells */$::MQ65_NAND2] area] 0]
    set all   [mq65_leaf *]
    set icg   [get_cells -quiet -hierarchical -filter "is_hierarchical==false && ref_name=~$::MQ65_ICG_PATTERN"]
    set flop  [remove_from_collection [all_registers -edge_triggered] $icg]
    set lat   [remove_from_collection [all_registers -level_sensitive] $icg]
    set comb  [remove_from_collection [remove_from_collection [remove_from_collection $all $flop] $lat] $icg]
    set rf     [mq65_leaf *u_sram/u_rf/*]
    set rf_lat [filter_collection $lat  "full_name=~*u_rf/*"]
    set rf_flp [filter_collection $flop "full_name=~*u_rf/*"]
    set rf_icg [filter_collection $icg  "full_name=~*u_rf/*"]
    set rf_cmb [filter_collection $comb "full_name=~*u_rf/*"]
    set a_all [mq65_area $all]
    puts $fh [format "total_cell_area_um2 %.1f" $a_all]
    puts $fh [format "nand2_area_um2 %.3f" $nand2]
    puts $fh [format "gate_equivalents %.0f" [expr {$a_all / $nand2}]]
    puts $fh [format "leaf_cells %d" [mq65_count $all]]
    puts $fh "breakdown (cells, area um2):"
    foreach {lbl c} [list comb $comb flops $flop latches $lat icg $icg \
                          rf_total $rf rf_latches $rf_lat rf_icg $rf_icg rf_flops $rf_flp rf_comb $rf_cmb] {
        set a [mq65_area $c]
        puts $fh [format "  %-11s %8d %12.1f  %5.1f %%" $lbl [mq65_count $c] $a [expr {100.0*$a/$a_all}]]
    }
    puts $fh "hierarchy (leaf-cell area um2, cells):"
    foreach {lbl inst} $::MQ65_HIER {
        set c [mq65_leaf $inst/*]
        puts $fh [format "  %-10s %-24s %12.1f %8d" $lbl $inst [mq65_area $c] [mq65_count $c]]
    }
    set top [remove_from_collection $all [mq65_leaf */*]]
    puts $fh [format "  %-10s %-24s %12.1f %8d" top_glue (top) [mq65_area $top] [mq65_count $top]]
}

# DC report_area category lines and report_power totals (default switching activity)
proc mq65_put_dc_reports {fh} {
    redirect -variable ra {report_area -nosplit}
    foreach k {Combinational Buf/Inv Noncombinational {Macro/Black Box} {Net Interconnect} {Total cell} Total} {
        if {[regexp -line "^$k area:\\s+(\[0-9.\]+)" $ra -> v]} { puts $fh [format "dc_area %-18s %s" $k $v] }
    }
    # power-group table "Total" row: internal, switching, leakage, total (default activity)
    redirect -variable rp {report_power -nosplit}
    if {[regexp -line {^Total\s+(\S+ \S+)\s+(\S+ \S+)\s+(\S+ \S+)\s+(\S+ \S+)} $rp -> pi ps pl pt]} {
        puts $fh "dc_power internal $pi  switching $ps  leakage $pl  total $pt  (default activity)"
    }
}

proc mq65_summary {path period corner topo} {
    set fh [open $path w]
    puts $fh "mq_chip 65 nm DC summary"
    puts $fh "period_ns $period  mode [expr {$topo ? {topographical} : {wire-load}}]  corner $corner ([mq65_oc $corner])"
    mq65_put_area $fh
    mq65_put_dc_reports $fh
    mq65_put_timing $fh
    close $fh
}
