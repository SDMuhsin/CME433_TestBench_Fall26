#!/bin/tcsh -f
# DC synthesis run on the server:  syn/scripts/run_dc.csh <period_ns> [corner=ss] [topo=1] [tag]
#   corner: ss | tt | ff (target library and RC corner); topo: 1 topographical, 0 wire-load
#   output: $MQ65/build/syn/<tag> (default <corner>_p<period>), summary copied to $MQ65/build/summary/
setenv MQ65 `cd $0:h/../.. && pwd`
source $MQ65/syn/common/env.csh
set period = $1
set corner = ss
if ($#argv >= 2) set corner = $2
set topo = 1
if ($#argv >= 3) set topo = $3
set tag = ${corner}_p$period
if ($#argv >= 4) set tag = $4
setenv MQ65_PERIOD $period
setenv MQ65_CORNER $corner
setenv MQ65_TOPO $topo
setenv MQ65_OUT $MQ65/build/syn/$tag
mkdir -p $MQ65_OUT $MQ65/build/summary
cd $MQ65_OUT
set mode = ""
if ($topo == 1) set mode = "-topographical_mode"
dc_shell $mode -f $MQ65/syn/scripts/dc_syn.tcl >& dc.log
if (-f summary.txt) cp -f summary.txt $MQ65/build/summary/syn_$tag.txt
echo "DC_DONE $tag errors(excl PROC-3) `grep '^Error' dc.log | grep -vc PROC-3`"
