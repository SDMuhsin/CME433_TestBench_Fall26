#!/bin/tcsh -f
# StarRC extraction of a routed block:  ext/run_star.csh <pnr_tag>
#   input  $MQ65/build/pnr/<pnr_tag>/out/mq_chip.def
#   output $MQ65/build/ext/<pnr_tag>/mq_chip.star_typ.spef (typical RC corner)
setenv MQ65 `cd $0:h/.. && pwd`
source $MQ65/syn/common/env.csh
set out = $MQ65/build/ext/$1
mkdir -p $out
cd $out
tclsh $MQ65/ext/star_cmd.tcl $MQ65/build/pnr/$1 $out
StarXtract -clean star_cmd >& star.log
set ok = 0
if (-f mq_chip.star_typ.spef) set ok = 1
echo "STAR_DONE $1 errors `grep -ci '^error' star.log` spef_written $ok"
