# mq_chip timing constraints for the 65 nm flow (DC and PrimeTime).
# Mirrors src_int8/flow/sdc/base.sdc (LibreLane base.sdc): one clock on port clk, IO delays
# = 20 % of the period on every non-clock port, driving cell on inputs, load on outputs,
# clock uncertainty / transition, DRV limits.  Caller sets:
#   ::mq_period  clock period, ns (40 = the GF180 chip's 25 MHz)
#   ::mq_lib     library name for driving cell / load lookup (mq65_lib ss)
# Latch RF: data is launched by the posedge write-data register (wd_r) and must pass the
# word latches (open while the gated clock is high) before they close at the falling edge
# of the SAME cycle.  This is the tool default for a flop -> positive latch path (capture
# window = the next closing edge after launch, i.e. the same high phase, with time borrowing
# up to the closing edge), so no multicycle exception is needed: a zero-cycle setup
# multicycle would move the window one full cycle earlier (seen in the first DC run).

set mq_io_pct      20.0
set mq_unc_setup   0.25
set mq_unc_hold    0.05
set mq_clk_tran    0.15
set mq_max_tran    [expr {min(0.50, 0.10 * $::mq_period)}]
set mq_max_fanout  16

create_clock -name clk -period $::mq_period [get_ports clk]
set_clock_uncertainty -setup $mq_unc_setup [get_clocks clk]
set_clock_uncertainty -hold  $mq_unc_hold  [get_clocks clk]
set_clock_transition $mq_clk_tran [get_clocks clk]

set mq_io_dly [expr {$::mq_period * $mq_io_pct / 100.0}]
set mq_inputs [remove_from_collection [all_inputs] [get_ports clk]]
set_input_delay  $mq_io_dly -clock clk $mq_inputs
set_output_delay $mq_io_dly -clock clk [all_outputs]

# reference cells from the site config (site/site.tcl)
set_driving_cell -lib_cell [lindex $::MQ65_DRV_IN 0]  -library $::mq_lib -pin [lindex $::MQ65_DRV_IN 1] $mq_inputs
set_driving_cell -lib_cell [lindex $::MQ65_DRV_CLK 0] -library $::mq_lib -pin [lindex $::MQ65_DRV_CLK 1] [get_ports clk]
set_load [expr {4.0 * [load_of $::mq_lib/$::MQ65_LOAD_PIN]}] [all_outputs]

set_max_transition $mq_max_tran [current_design]
set_max_fanout $mq_max_fanout [current_design]
