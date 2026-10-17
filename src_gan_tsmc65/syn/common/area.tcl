# gan65_chip area / summary writers (numbers and instance names only; safe to copy off the
# server). Uses the generic procs of src_int8_tsmc65/syn/common/summary.tcl (mq65_*).

# key hierarchies for the per-block table of mq65_put_area: label instance
set ::MQ65_HIER {
    host       u_host
    csr        u_csr
    seq        u_seq
    requant    u_seq/u_rq
    tanh_rom   u_seq/u_rq/u_rom
    dla        u_dla
    controller u_dla/u_controller
    a_buffer   u_dla/u_a_buffer
    b_buffer   u_dla/u_b_buffer
    pe_array   u_dla/u_pe_array
    c_buffer   u_dla/u_c_buffer
}

proc gan65_split_line {fh lbl cells total} {
    set a [mq65_area $cells]
    puts $fh [format "  %-14s %8d %12.1f  %5.1f %%" $lbl [mq65_count $cells] $a [expr {100.0*$a/$total}]]
    return $a
}

# total = PE array (16 PEs; the gan_mul8 instances inside) + latch-RF memories + rest
proc gan65_put_split {fh} {
    set all [mq65_leaf *]
    set tot [mq65_area $all]
    set pe  [mq65_leaf u_dla/u_pe_array/*]
    set mul [mq65_leaf u_dla/u_pe_array/*u_mul/*]
    set rf  [mq65_leaf *u_sram/u_rf/*]
    set npe [sizeof_collection [get_cells -quiet -hierarchical -filter "is_hierarchical==true && full_name=~u_dla/u_pe_array/*u_pe"]]
    set nmul [sizeof_collection [get_cells -quiet -hierarchical -filter "is_hierarchical==true && full_name=~u_dla/u_pe_array/*u_pe/u_mul"]]
    puts $fh "area_split (cells, area um2, % of total):"
    set a_pe [gan65_split_line $fh pe_array $pe $tot]
    set a_mul [gan65_split_line $fh mul8_all $mul $tot]
    gan65_split_line $fh pe_other [remove_from_collection $pe $mul] $tot
    set a_rf [gan65_split_line $fh latch_rf $rf $tot]
    gan65_split_line $fh rest [remove_from_collection [remove_from_collection $all $pe] $rf] $tot
    puts $fh [format "pe_instances %d  mul8_instances %d  mul8_area_per_instance_um2 %.1f  pe_area_per_instance_um2 %.1f" \
        $npe $nmul [expr {$nmul ? $a_mul / $nmul : 0}] [expr {$npe ? $a_pe / $npe : 0}]]
}

proc gan65_summary {path period corner variant} {
    set fh [open $path w]
    puts $fh "gan65_chip 65 nm DC summary"
    puts $fh "period_ns $period  mode topographical  corner $corner  multiplier $variant"
    mq65_put_area $fh
    gan65_put_split $fh
    mq65_put_dc_reports $fh
    mq65_put_timing $fh
    gan65_put_mul_timing $fh
    close $fh
}

# worst setup slack of the paths through a multiplier output (product -> accumulator)
proc gan65_put_mul_timing {fh} {
    set pins [get_pins -quiet -of_objects [get_cells -quiet -hierarchical \
        -filter "is_hierarchical==true && full_name=~u_dla/u_pe_array/*u_pe/u_mul"] -filter "direction==out"]
    if {![sizeof_collection $pins]} { return }
    set p [get_timing_paths -delay_type max -max_paths 1 -through $pins]
    puts $fh [format "setup_through_mul8 WNS %8.4f ns  worst path: %s -> %s (arrival %.3f ns)" \
        [get_attribute $p slack] [get_object_name [get_attribute $p startpoint]] \
        [get_object_name [get_attribute $p endpoint]] [get_attribute $p arrival]]
}
