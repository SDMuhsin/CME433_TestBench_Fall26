# Summary of a multiplier-bench run (numbers and instance names only; safe to copy off the
# server): areas of the multiplier (u_mul) and the registers, worst setup path through the
# multiplier, its a -> p delay inside u_mul and the period that path needs (period - slack).
proc mb_mul_path {} {
    set pins [get_pins -of_objects [get_cells u_mul] -filter "direction==out"]
    return [get_timing_paths -delay_type max -max_paths 1 -through $pins]
}
proc mb_mul_delay {p} {
    set t0 ""; set t1 0.0
    foreach_in_collection pt [get_attribute $p points] {
        if {[string first "u_mul/" [get_object_name [get_attribute $pt object]]] != 0} { continue }
        set a [get_attribute $pt arrival]
        if {$t0 eq ""} { set t0 $a }
        set t1 $a
    }
    return [expr {$t0 eq "" ? 0.0 : $t1 - $t0}]
}
proc mb_summary {path period corner} {
    set fh [open $path w]
    puts $fh "mul_bench 65 nm DC summary"
    puts $fh "width $::env(MB_N)  design $::env(MB_DESIGN)  period_ns $period  corner $corner  mode topographical"
    set all [mq65_leaf *]
    set mul [mq65_leaf u_mul/*]
    puts $fh [format "area_total_um2 %.1f  cells %d" [mq65_area $all] [mq65_count $all]]
    puts $fh [format "area_mul_um2 %.1f  cells %d" [mq65_area $mul] [mq65_count $mul]]
    puts $fh [format "area_regs_um2 %.1f" [mq65_area [remove_from_collection $all $mul]]]
    mq65_put_timing $fh
    set p [mb_mul_path]
    set s [get_attribute $p slack]
    puts $fh [format "mul_path slack %.4f ns  arrival %.4f ns  %s -> %s" $s [get_attribute $p arrival] \
        [get_object_name [get_attribute $p startpoint]] [get_object_name [get_attribute $p endpoint]]]
    puts $fh [format "mul_a_to_p_delay_ns %.4f" [mb_mul_delay $p]]
    puts $fh [format "min_period_ns %.4f  (period - slack of the path through u_mul)" [expr {$period - $s}]]
    close $fh
}
