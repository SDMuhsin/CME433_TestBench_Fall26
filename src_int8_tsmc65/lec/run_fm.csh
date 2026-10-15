#!/bin/tcsh -f
# Formality run on the server:  lec/run_fm.csh <syn_tag>     (e.g. ss_p4)
#   library corner = the DC run's target corner (prefix of syn_tag)
#   output: $MQ65/build/lec/<syn_tag>/, summary copied to $MQ65/build/summary/fm_<syn_tag>.txt
setenv MQ65 `cd $0:h/.. && pwd`
source $MQ65/syn/common/env_pt.csh
setenv MQ65_SYN $MQ65/build/syn/$1
setenv MQ65_CORNER `echo $1 | sed 's/_p.*//'`
setenv MQ65_TAG fm_$1
setenv MQ65_OUT $MQ65/build/lec/$1
mkdir -p $MQ65_OUT $MQ65/build/summary
cd $MQ65_OUT
fm_shell -f $MQ65/lec/fm_lec.tcl >& fm.log
if (-f summary.txt) cp -f summary.txt $MQ65/build/summary/$MQ65_TAG.txt
echo "FM_DONE $MQ65_TAG errors `grep -c '^Error' fm.log` `grep -m1 -E 'Verification (SUCCEEDED|FAILED|INCONCLUSIVE)' fm.log`"
