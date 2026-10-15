# Latch-RF timing digest for the STA summary: time borrowing into the word latches and the
# read path launched from them (latch Q -> read mux -> q_r).
proc mq65_latch_q_pins {} {
    return [get_pins -of_objects [all_registers -level_sensitive] -filter "direction==out"]
}

# time borrowed at the worst latch endpoint, parsed from the path report
proc mq65_borrow_of {path_cmd} {
    redirect -variable r $path_cmd
    if {[regexp {time borrowed from endpoint\s+(-?[0-9.]+)} $r -> b]} { return $b }
    return 0.0
}

proc mq65_put_latch {fh} {
    set d [all_registers -level_sensitive -data_pins]
    set p [get_timing_paths -delay_type max -max_paths 1 -to $d]
    set borrow [mq65_borrow_of {report_timing -to $d -max_paths 1 -nosplit}]
    set nb [sizeof_collection [get_timing_paths -delay_type max -to $d -max_paths 100000 \
                                 -nworst 1 -slack_lesser_than 0.00001]]
    puts $fh [format "latch_in  slack %8.4f ns  borrowed %.4f ns  latch endpoints at slack 0 (borrowing) %d of %d" \
        [get_attribute $p slack] $borrow $nb [sizeof_collection $d]]
    puts $fh "       worst path: [get_object_name [get_attribute $p startpoint]] -> [get_object_name [get_attribute $p endpoint]] (arrival [format %.3f [get_attribute $p arrival]] ns)"
    set q [get_timing_paths -delay_type max -max_paths 1 -through [mq65_latch_q_pins]]
    puts $fh [format "latch_out slack %8.4f ns  (RF read path, through latch Q)" [get_attribute $q slack]]
    puts $fh "       worst path: [get_object_name [get_attribute $q startpoint]] -> [get_object_name [get_attribute $q endpoint]] (arrival [format %.3f [get_attribute $q arrival]] ns)"
    set h [get_timing_paths -delay_type min -max_paths 1 -to $d]
    puts $fh [format "latch_in  hold slack %8.4f ns" [get_attribute $h slack]]
}
