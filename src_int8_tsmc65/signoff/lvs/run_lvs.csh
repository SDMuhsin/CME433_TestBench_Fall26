#!/bin/tcsh -f
# Calibre LVS of the routed block (core level):  signoff/lvs/run_lvs.csh <pnr_tag>
#   layout $MQ65/build/pnr/<pnr_tag>/out/mq_chip.gds
#   source $MQ65/build/pnr/<pnr_tag>/out/mq_chip.lvs.v (PG netlist) -> SPICE with v2lvs,
#          cell subcircuits from the site config (MQ65_CDL)
#   compare: hierarchical, library cells matched by name (-automatch) and compared once each
#   output: $MQ65/build/signoff/<pnr_tag>/lvs/ (lvs.rep), digest -> build/summary/
setenv MQ65 `cd $0:h/../.. && pwd`
source $MQ65/syn/common/env.csh
set pnr = $MQ65/build/pnr/$1/out
set out = $MQ65/build/signoff/$1/lvs
mkdir -p $out $MQ65/build/summary
cd $out
set deck = `tclsh $MQ65/syn/common/site_get.tcl MQ65_LVS_DECK`
set cdl  = `tclsh $MQ65/syn/common/site_get.tcl MQ65_CDL`
set pg   = (`tclsh $MQ65/syn/common/site_get.tcl MQ65_PG`)
# filler cells have no devices and no subcircuit in the cell netlist: empty stubs
tclsh $MQ65/signoff/lvs/filler_stubs.tcl > fillers.sp
v2lvs -v $pnr/mq_chip.lvs.v -o source.sp -s $cdl -s fillers.sp -s1 $pg[1] -s0 $pg[2] >& v2lvs.log
$MQ65/signoff/lvs/runset.sh $deck $pnr/mq_chip.gds $out/source.sp mq_chip $pg[1] $pg[2] > runset.svrf
calibre -lvs -hier -automatch -turbo 8 runset.svrf >& lvs.log
$MQ65/signoff/lvs/digest.sh lvs.rep > summary.txt
cp -f summary.txt $MQ65/build/summary/lvs_$1.txt
echo "LVS_DONE $1 `head -3 summary.txt | tr '\n' ' '`"
