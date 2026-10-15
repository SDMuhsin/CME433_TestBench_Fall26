#!/bin/tcsh -f
# ICC2 place and route of a DC netlist:  pnr/run_pnr.csh <syn_tag> <period> [util=0.65] [first_stage]
#   stages (one icc2_shell session each; snapshot block mq_chip_<stage> after each):
#     floorplan place cts route finish
#   output: $MQ65/build/pnr/<syn_tag>/ (mq65.nlib, rpt/, out/, <stage>.log)
#   needs the reference library from pnr/ndm/run_ndm.csh
setenv MQ65 `cd $0:h/.. && pwd`
source $MQ65/syn/common/env_pt.csh
setenv MQ65_SYN $MQ65/build/syn/$1
setenv MQ65_PERIOD $2
setenv MQ65_UTIL 0.65
if ($#argv >= 3) setenv MQ65_UTIL $3
setenv MQ65_PNR $MQ65/build/pnr/$1
set stages = (floorplan place cts route finish)
if ($#argv >= 4) then
    while ("$stages[1]" != "$4")
        shift stages
    end
endif
mkdir -p $MQ65_PNR
cd $MQ65_PNR
foreach s ($stages)
    echo "STAGE_START $s `date +%H:%M:%S`"
    icc2_shell -f $MQ65/pnr/$s/$s.tcl >& $s.log
    if (`grep -c "STAGE_OK $s" $s.log` == 0) then
        echo "PNR_FAIL $s (`grep -c '^Error' $s.log` errors, $MQ65_PNR/$s.log)"
        exit 1
    endif
end
echo "PNR_DONE $1 `date +%H:%M:%S`"
