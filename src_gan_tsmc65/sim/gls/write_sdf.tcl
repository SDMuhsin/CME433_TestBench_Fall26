# PrimeTime: SDF of a gan65 DC netlist for timing-annotated GLS (pre-layout, DC SPEF).
# Environment (set by sim/gls/run_sdf.csh): GAN65 MQ65 GAN65_SYN GAN65_CORNER GAN65_RC
#   GAN65_PERIOD GAN65_SDF
# There is no clock tree before layout: the root clock net is ideal (zero delay and skew),
# so the simulated clock reaches every sink at once, as in the STA with ideal clocks.
source $::env(GAN65)/syn/common/pt_load.tcl
gan65_pt_load $::env(GAN65_SYN) $::env(GAN65_CORNER) $::env(GAN65_RC) $::env(GAN65_PERIOD)
set_ideal_network [get_ports clk]
update_timing -full
write_sdf -version 3.0 -context verilog $::env(GAN65_SDF)
exit
