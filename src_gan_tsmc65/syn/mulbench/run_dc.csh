#!/bin/tcsh -f
# DC topographical synthesis of mul_bench on the server:
#   syn/mulbench/run_dc.csh <width 8|16> <design> <period_ns> [corner=ss]
#   output $GAN65/build/mulbench/w<N>_<design>_p<period>/, summary copied to
#   $GAN65/build/summary/mb_w<N>_<design>_p<period>.txt
setenv GAN65 `cd $0:h/../.. && pwd`
source $GAN65/syn/common/env.csh
setenv MB_N $1
setenv MB_DESIGN $2
setenv MB_PERIOD $3
setenv MB_CORNER ss
if ($#argv >= 4) setenv MB_CORNER $4
set tag = w$1_$2_p$3
setenv MB_OUT $GAN65/build/mulbench/$tag
mkdir -p $MB_OUT $GAN65/build/summary
echo $MB_CORNER > $MB_OUT/corner
cd $MB_OUT
dc_shell -topographical_mode -f $GAN65/syn/mulbench/dc_mul.tcl >& dc.log
if (-f summary.txt) cp -f summary.txt $GAN65/build/summary/mb_$tag.txt
echo "DC_DONE $tag errors `grep -c '^Error' dc.log`"
