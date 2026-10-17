#!/bin/tcsh -f
# Write the SDF of a DC netlist (server):  sim/gls/run_sdf.csh <syn_tag> [corner=tt] [period=2.0]
#   output $GAN65/build/syn/<syn_tag>/gan65_chip.<corner>.sdf (rc max; min at ff), log sdf_<corner>.log
setenv GAN65 `cd $0:h/../.. && pwd`
source $GAN65/syn/common/env_pt.csh
set corner = tt
if ($#argv >= 2) set corner = $2
set rc = max
if ($corner == ff) set rc = min
setenv GAN65_SYN $GAN65/build/syn/$1
setenv GAN65_CORNER $corner
setenv GAN65_RC $rc
setenv GAN65_PERIOD 2.0
if ($#argv >= 3) setenv GAN65_PERIOD $3
setenv GAN65_SDF $GAN65_SYN/gan65_chip.$corner.sdf
cd $GAN65_SYN
pt_shell -f $GAN65/sim/gls/write_sdf.tcl >& sdf_$corner.log
set ok = FAIL
if (-s $GAN65_SDF) set ok = OK
echo "SDF_DONE $1 $corner $ok errors `grep -c '^Error' sdf_$corner.log`"
