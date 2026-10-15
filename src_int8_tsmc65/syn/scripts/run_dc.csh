#!/bin/tcsh -f
# DC synthesis run on the server:  syn/scripts/run_dc.csh <period_ns> [topo=1] [tag]
#   output: $MQ65/out/syn/<tag>  (default tag p<period>), summary.txt copied to $MQ65/out/summary/
source $HOME/mq65/env.csh
set period = $1
set topo = 1
if ($#argv >= 2) set topo = $2
set tag = p$period
if ($#argv >= 3) set tag = $3
setenv MQ65_PERIOD $period
setenv MQ65_TOPO $topo
setenv MQ65_OUT $MQ65/out/syn/$tag
mkdir -p $MQ65_OUT $MQ65/out/summary
cd $MQ65_OUT
if ($topo == 1) then
    dc_shell -topographical_mode -f $MQ65/syn/scripts/dc_syn.tcl >& dc.log
else
    dc_shell -f $MQ65/syn/scripts/dc_syn.tcl >& dc.log
endif
cp -f summary.txt $MQ65/out/summary/syn_$tag.txt
grep -c "^Error" dc.log
