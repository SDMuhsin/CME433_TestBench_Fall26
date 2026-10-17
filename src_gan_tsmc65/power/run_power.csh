#!/bin/tcsh -f
# PrimePower run on the server:  power/run_power.csh <syn_tag> <gls_tag> [corner=tt] [rc] [period]
#   netlist  $GAN65/build/syn/<syn_tag>; SAIF $GAN65/build/gls/<gls_tag>/gan65_chip.saif
#   rc       max (default) | min (default at ff) | none; period default = the SAIF's clock
#   output   $GAN65/build/power/<syn_tag>_<gls_tag>_<corner>/, summary copied to
#            $GAN65/build/summary/pwr_<same>.txt
setenv GAN65 `cd $0:h/.. && pwd`
source $GAN65/syn/common/env_pt.csh
set corner = tt
if ($#argv >= 3) set corner = $3
set rc = max
if ($corner == ff) set rc = min
if ($#argv >= 4) set rc = $4
set gls = $GAN65/build/gls/$2
if (! -f $gls/gan65_chip.saif) then
    echo "PWR_DONE $1_$2_$corner no SAIF in $gls"; exit 1
endif
set period = `$GAN65/sim/gls/saif_period.sh $gls`
if ($#argv >= 5) set period = $5
setenv GAN65_ACT "SAIF from zero-delay GLS (no glitches)"
if (-f $gls/activity) setenv GAN65_ACT "`cat $gls/activity`"
setenv GAN65_SYN $GAN65/build/syn/$1
setenv GAN65_SAIF $gls/gan65_chip.saif
setenv GAN65_CORNER $corner
setenv GAN65_RC $rc
setenv GAN65_PERIOD $period
# clocks per image (bench: reset to last pixel read; docs/bench.md), same for every variant
setenv GAN65_CLK_IMG 2346721
setenv GAN65_TAG pwr_$1_$2_$corner
setenv GAN65_OUT $GAN65/build/power/$1_$2_$corner
mkdir -p $GAN65_OUT $GAN65/build/summary
cd $GAN65_OUT
pt_shell -f $GAN65/power/pp_power.tcl >& pp.log
if (-f summary.txt) cp -f summary.txt $GAN65/build/summary/$GAN65_TAG.txt
echo "PWR_DONE $GAN65_TAG errors `grep -c '^Error' pp.log`"
