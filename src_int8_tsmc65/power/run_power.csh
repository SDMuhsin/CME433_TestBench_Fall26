#!/bin/tcsh -f
# PrimeTime PX run on the server:  power/run_power.csh <syn_tag> <gls_tag> [corner] [rc=max] [period]
#   netlist $MQ65/build/syn/<syn_tag>; SAIF $MQ65/build/gls/<gls_tag>/mq_chip.saif
#   corner default = prefix of syn_tag; period default from syn_tag (<corner>_p<period>)
#   output: $MQ65/build/power/<syn_tag>_<gls_tag>/, summary -> $MQ65/build/summary/pwr_<...>.txt
setenv MQ65 `cd $0:h/.. && pwd`
source $MQ65/syn/common/env_pt.csh
setenv MQ65_SYN $MQ65/build/syn/$1
setenv MQ65_SAIF $MQ65/build/gls/$2/mq_chip.saif
setenv MQ65_CORNER `echo $1 | sed 's/_p.*//'`
if ($#argv >= 3) setenv MQ65_CORNER $3
setenv MQ65_RC max
if ($#argv >= 4) setenv MQ65_RC $4
setenv MQ65_PERIOD `echo $1 | sed 's/.*_p//'`
if ($#argv >= 5) setenv MQ65_PERIOD $5
setenv MQ65_TAG pwr_$1_$2
setenv MQ65_OUT $MQ65/build/power/$1_$2
mkdir -p $MQ65_OUT $MQ65/build/summary
cd $MQ65_OUT
pt_shell -f $MQ65/power/pp_power.tcl >& pp.log
if (-f summary.txt) cp -f summary.txt $MQ65/build/summary/$MQ65_TAG.txt
echo "PWR_DONE $MQ65_TAG errors `grep -c '^Error' pp.log`"
