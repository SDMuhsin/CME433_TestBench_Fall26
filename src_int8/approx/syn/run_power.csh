#!/bin/tcsh -f
# Gate-level power of one standalone mq_mul8 netlist on the server:
#   src_int8/approx/syn/run_power.csh <syn_tag> <vec> [period_ns=10]
#     <syn_tag>  a run_dc.csh output (<repo>/build/approx/syn/<syn_tag>/)
#     <vec>      random | chip: <repo>/build/approx/act/vec_<vec>.hex (src_int8.approx.act.vectors,
#                copied to the server's clone with rsync)
#   1. VCS timing simulation of the netlist with the DC SDF (glitches included), one vector per
#      period, SAIF of the 65,536-operation window and an output checksum (tb_mul8_power.v)
#   2. PrimePower (averaged) with that SAIF at the netlist's corner
#   output: <repo>/build/approx/power/<syn_tag>_<vec>/, summary -> build/approx/summary/pwr_<...>.txt
set APX = `cd $0:h/.. && pwd`
set REPO = $APX:h:h
setenv MQ65 $REPO/src_int8_tsmc65
source $MQ65/syn/common/env_pt.csh
set syn = $REPO/build/approx/syn/$1
set period = 10
if ($#argv >= 3) set period = $3
set out = $REPO/build/approx/power/$1_$2
mkdir -p $out $REPO/build/approx/summary
cd $out
vcs -full64 -sverilog +lint=none +neg_tchk +notimingcheck -v $MQ65_VLOG -top tb_mul8_power \
    $syn/mq_mul8.v $APX/syn/tb_mul8_power.v -o simv >& compile.log
if (! -x simv) then
    echo "PWR_DONE $1_$2 compile FAILED (compile.log)"; exit 1
endif
./simv +VEC=$REPO/build/approx/act/vec_$2.hex +PERIOD=$period +SDF=$syn/mq_mul8.sdf \
    +SAIF=$out/mq_mul8.saif >& sim.log
setenv MUL8_SYN $syn
setenv MUL8_SAIF $out/mq_mul8.saif
setenv MUL8_PERIOD $period
setenv MUL8_CORNER `grep '^corner' $syn/summary.txt | awk '{print $2}'`
setenv MUL8_TAG $1_$2
pt_shell -f $APX/syn/pp_mul8.tcl >& pp.log
grep CHECKSUM sim.log >> summary.txt
if (-f summary.txt) cp -f summary.txt $REPO/build/approx/summary/pwr_$1_$2.txt
echo "PWR_DONE $1_$2 `grep CHECKSUM sim.log` errors `grep -c '^Error' pp.log`"
