# Post-layout Fmax sweep in PrimeTime: one load of the routed netlist + SPEF, then the
# constraints are re-applied at each period of MQ65_PERIODS (IO delays scale with the
# period as in synthesis) and the setup / hold WNS recorded.  The layout is not changed.
# Environment: as pt_post.tcl, plus MQ65_PERIODS (space-separated, ns)
source $::env(MQ65)/syn/common/pt_load.tcl
source $::env(MQ65)/syn/common/summary.tcl
set out $::env(MQ65_OUT)
mq65_pt_load_post $::env(MQ65_NETLIST) $::env(MQ65_CORNER) $::env(MQ65_SPEF) $::env(MQ65_PERIOD)
set fh [open $out/summary.txt w]
puts $fh "mq_chip 65 nm post-layout Fmax sweep ($::env(MQ65_TAG)), corner $::env(MQ65_CORNER), parasitics $::env(MQ65_RCLABEL), propagated clocks"
foreach p $::env(MQ65_PERIODS) {
    set ::mq_period $p
    source $::env(MQ65)/syn/constraints/mq65.sdc
    set_propagated_clock [all_clocks]
    update_timing
    lassign [mq65_slack max] wns tns nv sp ep
    lassign [mq65_slack min] hwns
    puts $fh [format "period %.3f ns  setup WNS %8.4f  TNS %9.3f  violating %d  hold WNS %8.4f  worst: %s -> %s" \
        $p $wns $tns $nv $hwns $sp $ep]
    flush $fh
}
close $fh
exit
