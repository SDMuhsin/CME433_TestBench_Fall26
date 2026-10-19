#!/bin/tcsh -f
# DC topographical synthesis on the server:
#   syn/scripts/run_dc.csh <period_ns> [corner=ss] [variant=exact] [tag]
#   corner : ss | tt | ff (target library and RC corner)
#   variant: multiplier, as bench/variant.py resolves it (exact | <name> | mq:<name> | mb:<d> | path)
#   env GAN65_WIDTH: datapath width 8 (default) | 16; tags of width 16 runs are <variant>_w16_...
#   output : $GAN65/build/syn/<tag> (default <variant>_<corner>_p<period>),
#            summary copied to $GAN65/build/summary/syn_<tag>.txt
setenv GAN65 `cd $0:h/../.. && pwd`
source $GAN65/syn/common/env.csh
set period = $1
set corner = ss
if ($#argv >= 2) set corner = $2
set variant = exact
if ($#argv >= 3) set variant = $3
if (! $?GAN65_WIDTH) setenv GAN65_WIDTH 8
set vname = `cd $GAN65:h && python3 -m src_gan_tsmc65.bench.variant --name $variant --width $GAN65_WIDTH`
set tag = ${vname}_${corner}_p$period
if ($#argv >= 4) set tag = $4
setenv GAN65_PERIOD $period
setenv GAN65_CORNER $corner
setenv GAN65_VARIANT $variant
setenv GAN65_OUT $GAN65/build/syn/$tag
setenv GAN65_MUL_F $GAN65_OUT/mul.f
mkdir -p $GAN65_OUT $GAN65/build/summary
(cd $GAN65:h && python3 -m src_gan_tsmc65.bench.variant --width $GAN65_WIDTH $variant) > $GAN65_MUL_F
if ($status != 0) then
    echo "DC_DONE $tag variant $variant not found"; exit 1
endif
echo $corner > $GAN65_OUT/corner
echo $GAN65_WIDTH > $GAN65_OUT/width
cd $GAN65_OUT
dc_shell -topographical_mode -f $GAN65/syn/scripts/dc_syn.tcl >& dc.log
if (-f summary.txt) cp -f summary.txt $GAN65/build/summary/syn_$tag.txt
echo "DC_DONE $tag errors(excl PROC-3) `grep '^Error' dc.log | grep -vc PROC-3`"
