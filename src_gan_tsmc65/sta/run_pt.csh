#!/bin/tcsh -f
# PrimeTime STA run on the server:  sta/run_pt.csh <syn_tag> <corner> [rc=max] [period]
#   syn_tag: DC run in $GAN65/build/syn/<syn_tag> (e.g. exact_ss_p2.5); corner: ss | tt | ff
#   rc: max | min | none (DC estimated SPEF); period: default from syn_tag (..._p<period>)
#   output: $GAN65/build/sta/<syn_tag>_<corner>_<rc>[_at<period>]/, summary copied to
#           $GAN65/build/summary/sta_<same>.txt
setenv GAN65 `cd $0:h/.. && pwd`
source $GAN65/syn/common/env_pt.csh
set rc = max
if ($#argv >= 3) set rc = $3
set period = `echo $1 | sed 's/.*_p//'`
set sfx = ""
if ($#argv >= 4) then
    if ("$4" != "$period") set sfx = _at$4
    set period = $4
endif
setenv GAN65_SYN $GAN65/build/syn/$1
setenv GAN65_CORNER $2
setenv GAN65_RC $rc
setenv GAN65_PERIOD $period
setenv GAN65_TAG sta_$1_$2_$rc$sfx
setenv GAN65_OUT $GAN65/build/sta/$1_$2_$rc$sfx
mkdir -p $GAN65_OUT $GAN65/build/summary
cd $GAN65_OUT
pt_shell -f $GAN65/sta/pt_sta.tcl >& pt.log
if (-f summary.txt) cp -f summary.txt $GAN65/build/summary/$GAN65_TAG.txt
echo "PT_DONE $GAN65_TAG errors `grep -c '^Error' pt.log`"
