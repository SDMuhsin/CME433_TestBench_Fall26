#!/bin/tcsh -f
# Calibre DRC of the routed block (core level):  signoff/drc/run_drc.csh <pnr_tag> [deck_var=MQ65_DRC_DECK]
#   layout $MQ65/build/pnr/<pnr_tag>/out/mq_chip.gds; deck from the site config
#   (MQ65_DRC_DECK main rules, MQ65_ANT_DECK antenna rules)
#   output: $MQ65/build/signoff/<pnr_tag>/<deck_var>/ (drc.sum, drc.results), digest -> build/summary/
setenv MQ65 `cd $0:h/../.. && pwd`
source $MQ65/syn/common/env.csh
set dv = MQ65_DRC_DECK
if ($#argv >= 2) set dv = $2
set out = $MQ65/build/signoff/$1/$dv
mkdir -p $out $MQ65/build/summary
cd $out
set deck = `tclsh $MQ65/syn/common/site_get.tcl $dv`
$MQ65/signoff/drc/runset.sh $deck $MQ65/build/pnr/$1/out/mq_chip.gds mq_chip > runset.svrf
calibre -drc -hier -turbo 8 runset.svrf >& drc.log
$MQ65/signoff/drc/digest.sh drc.sum > summary.txt
cp -f summary.txt $MQ65/build/summary/drc_$1_$dv.txt
echo "DRC_DONE $1 $dv `grep -E '^total' summary.txt`"
