#!/bin/tcsh -f
# Build the ICC2 reference library:  pnr/ndm/run_ndm.csh   -> $MQ65/build/pnr/ndm/mq65_std.ndm
setenv MQ65 `cd $0:h/../.. && pwd`
source $MQ65/syn/common/env_pt.csh
setenv MQ65_OUT $MQ65/build/pnr/ndm
mkdir -p $MQ65_OUT
cd $MQ65_OUT
icc2_lm_shell -f $MQ65/pnr/ndm/make_ndm.tcl >& lm.log
echo "NDM_DONE errors `grep -c '^Error' lm.log` `grep NDM_OK lm.log`"
