# Shared OpenSTA setup of one signoff corner of the routed mb_chip (sourced by
# sdf_gls/sdf/write_sdf.tcl and power/report/power.tcl).  Same inputs as LibreLane
# OpenROAD.STAPostPNR (step 76): std-cell + fd_io + SRAM Liberty of the corner's PVT, final
# netlist, the corner's RC SPEF (min/nom/max = first token of the corner name), src/flow/sdc/signoff.sdc
# with the run's SDC variables (resolved.json values), propagated clocks.
#   in:  ::env(RUN) ::env(CORNER) [::env(CLOCK_PERIOD_OVERRIDE)]  [::mb_extra_libs: more .lib]
#   out: ::corner ::rc ::pvt ::libs ::spef ::flow (src/flow) ::root (repo)
set ::corner $::env(CORNER)
set ::rc [lindex [split $::corner _] 0]
set ::pvt [join [lrange [split $::corner _] 1 end] _]
set ::flow [file dirname [file dirname [file normalize [info script]]]]
set ::root [file dirname [file dirname $::flow]]
set _pdk $::env(PDK_ROOT)/gf180mcuD/libs.ref
array set _io_lib {tt_025C_3v30 tt_025C_3v30 ff_n40C_3v60 ff_n40C_3v63 ss_125C_3v00 ss_125C_2v97}
set ::libs [list \
    $_pdk/gf180mcu_as_sc_mcu7t3v3/lib/gf180mcu_as_sc_mcu7t3v3__$::pvt.lib \
    $_pdk/gf180mcu_fd_io/lib/gf180mcu_fd_io__$_io_lib($::pvt).lib \
    $::root/gf180mcu_ocd_ip_sram__sram256x8m8wm1/gf180mcu_ocd_ip_sram__sram256x8m8wm1__$::pvt.lib]
if {[info exists ::mb_extra_libs]} { set ::libs [concat $::libs $::mb_extra_libs] }
foreach {k v} {
    CLOCK_PORT clk CLOCK_PERIOD 40.0 IO_DELAY_CONSTRAINT 20.0 MAX_FANOUT_CONSTRAINT 9
    MAX_TRANSITION_CONSTRAINT 1.5 OUTPUT_CAP_LOAD 72.91 CLOCK_UNCERTAINTY_CONSTRAINT 0.25
    CLOCK_TRANSITION_CONSTRAINT 0.15 TIME_DERATING_CONSTRAINT 5.0
    SYNTH_DRIVING_CELL gf180mcu_as_sc_mcu7t3v3__inv_2/Y
    SYNTH_CLK_DRIVING_CELL gf180mcu_as_sc_mcu7t3v3__inv_4/Y
} { set ::env($k) $v }
if {[info exists ::env(CLOCK_PERIOD_OVERRIDE)]} { set ::env(CLOCK_PERIOD) $::env(CLOCK_PERIOD_OVERRIDE) }
set ::spef $::env(RUN)/final/spef/$::rc/mb_chip.$::rc.spef

define_corners $::corner
foreach l $::libs { read_liberty -corner $::corner $l }
read_verilog $::env(RUN)/final/nl/mb_chip.nl.v
link_design mb_chip
read_sdc $::flow/sdc/signoff.sdc
read_spef -corner $::corner $::spef
