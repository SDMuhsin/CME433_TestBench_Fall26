#!/bin/tcsh -f
# Post-layout PrimeTime PX run:  power/post/run_power_post.csh <pnr_tag> <gls_tag> [corner=tt] [rc=star] [period=4]
#   netlist $MQ65/build/pnr/<pnr_tag>/out/mq_chip.v, SAIF $MQ65/build/gls/<gls_tag>/mq_chip.saif
#   rc: star (StarRC typical) | icc2_<corner> (ICC2 TLU+ extraction), as sta/post/run_pt_post.csh
#   output: $MQ65/build/power_post/<pnr_tag>_<gls_tag>_<corner>_p<period>/, summary -> build/summary/
setenv MQ65 `cd $0:h/../.. && pwd`
source $MQ65/syn/common/env_pt.csh
set pnr = $MQ65/build/pnr/$1
setenv MQ65_NETLIST $pnr/out/mq_chip.v
setenv MQ65_SAIF $MQ65/build/gls/$2/mq_chip.saif
setenv MQ65_CORNER tt
if ($#argv >= 3) setenv MQ65_CORNER $3
setenv MQ65_RCLABEL star
if ($#argv >= 4) setenv MQ65_RCLABEL $4
setenv MQ65_PERIOD 4
if ($#argv >= 5) setenv MQ65_PERIOD $5
setenv MQ65_SPEF `$MQ65/sta/post/spef_path.sh $1 $MQ65_RCLABEL`
setenv MQ65_TAG pwrpost_$1_$2_${MQ65_CORNER}_p$MQ65_PERIOD
setenv MQ65_OUT $MQ65/build/power_post/$1_$2_${MQ65_CORNER}_p$MQ65_PERIOD
mkdir -p $MQ65_OUT $MQ65/build/summary
cd $MQ65_OUT
pt_shell -f $MQ65/power/post/pp_post.tcl >& pp.log
if (-f summary.txt) cp -f summary.txt $MQ65/build/summary/$MQ65_TAG.txt
echo "PWR_DONE $MQ65_TAG errors `grep -c '^Error' pp.log`"
