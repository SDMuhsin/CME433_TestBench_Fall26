#!/bin/tcsh -f
# PrimeTime STA run on the server:  sta/run_pt.csh <syn_tag> <corner> [rc=max] [period]
#   syn_tag: DC run in $MQ65/build/syn/<syn_tag> (e.g. ss_p4); corner: ss | tt | ff
#   rc: max | min | none (DC estimated SPEF); period: default from syn_tag (<corner>_p<period>)
#   MQ65_PT_SCRIPT=<name> runs sta/<name>.tcl instead of pt_sta.tcl (e.g. pt_corr)
#   output: $MQ65/build/sta/<syn_tag>_<corner>_<rc>[_at<period>]/, summary copied to $MQ65/build/summary/
setenv MQ65 `cd $0:h/.. && pwd`
source $MQ65/syn/common/env_pt.csh
set rc = max
if ($#argv >= 3) set rc = $3
set period = `echo $1 | sed 's/.*_p//'`
set sfx = ""
if ($#argv >= 4) then
    if ("$4" != "$period") set sfx = _at$4
    set period = $4
endif
setenv MQ65_SYN $MQ65/build/syn/$1
setenv MQ65_CORNER $2
setenv MQ65_RC $rc
setenv MQ65_PERIOD $period
setenv MQ65_TAG sta_$1_$2_$rc$sfx
set script = pt_sta
if ($?MQ65_PT_SCRIPT) then
    set script = $MQ65_PT_SCRIPT
endif
setenv MQ65_OUT $MQ65/build/sta/$1_$2_$rc$sfx
if ($script != pt_sta) setenv MQ65_OUT $MQ65_OUT.$script
mkdir -p $MQ65_OUT $MQ65/build/summary
cd $MQ65_OUT
pt_shell -f $MQ65/sta/$script.tcl >& pt.log
if (-f summary.txt) cp -f summary.txt $MQ65/build/summary/$MQ65_TAG.txt
echo "PT_DONE $MQ65_TAG errors `grep -c '^Error' pt.log`"
