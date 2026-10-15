#!/bin/tcsh -f
# Post-layout PrimeTime run:  sta/post/run_pt_post.csh <pnr_tag> <corner> <rc> [period=4]
#   netlist $MQ65/build/pnr/<pnr_tag>/out/mq_chip.v
#   rc: star     StarRC typical-corner SPEF ($MQ65/build/ext/<pnr_tag>/)
#       icc2_<c> ICC2 SPEF with the TLU+ model of corner <c> (ss worst, tt typical, ff best)
#   MQ65_PT_SCRIPT=<name> runs sta/post/<name>.tcl instead of pt_post.tcl (e.g. pt_fmax)
#   output: $MQ65/build/sta_post/<pnr_tag>_<corner>_<rc>[_at<period>]/, summary -> build/summary/
setenv MQ65 `cd $0:h/../.. && pwd`
source $MQ65/syn/common/env_pt.csh
set pnr = $MQ65/build/pnr/$1
setenv MQ65_NETLIST $pnr/out/mq_chip.v
setenv MQ65_CORNER $2
setenv MQ65_RCLABEL $3
setenv MQ65_SPEF `$MQ65/sta/post/spef_path.sh $1 $3`
setenv MQ65_PERIOD 4
set sfx = ""
if ($#argv >= 4) then
    setenv MQ65_PERIOD $4
    if ("$4" != "4") set sfx = _at$4
endif
set script = pt_post
if ($?MQ65_PT_SCRIPT) then
    set script = $MQ65_PT_SCRIPT
endif
setenv MQ65_TAG stapost_$1_$2_$3$sfx
setenv MQ65_OUT $MQ65/build/sta_post/$1_$2_$3$sfx
if ($script != pt_post) then
    setenv MQ65_OUT $MQ65_OUT.$script
    setenv MQ65_TAG ${MQ65_TAG}_$script
endif
mkdir -p $MQ65_OUT $MQ65/build/summary
cd $MQ65_OUT
pt_shell -f $MQ65/sta/post/$script.tcl >& pt.log
if (-f summary.txt) cp -f summary.txt $MQ65/build/summary/$MQ65_TAG.txt
echo "PT_DONE $MQ65_TAG errors `grep -c '^Error' pt.log`"
