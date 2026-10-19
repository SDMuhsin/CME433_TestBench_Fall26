#!/bin/tcsh -f
# Formality of a mul_bench DC run:  syn/mulbench/run_fm.csh <syn_tag> (w<N>_<design>_p<period>)
#   output $GAN65/build/mulbench/<syn_tag>/fm/, summary copied to $GAN65/build/summary/mbfm_<syn_tag>.txt
setenv GAN65 `cd $0:h/../.. && pwd`
source $GAN65/syn/common/env_pt.csh
setenv MB_SYN $GAN65/build/mulbench/$1
setenv MB_CORNER `cat $MB_SYN/corner`
setenv MB_N `echo $1 | sed -E 's/^w([0-9]+)_.*/\1/'`
setenv MB_DESIGN `echo $1 | sed -E 's/^w[0-9]+_(.*)_p[0-9.]+$/\1/'`
setenv MB_OUT $MB_SYN/fm
mkdir -p $MB_OUT
cd $MB_OUT
fm_shell -f $GAN65/syn/mulbench/fm_mul.tcl >& fm.log
if (-f summary.txt) cp -f summary.txt $GAN65/build/summary/mbfm_$1.txt
echo "FM_DONE $1 `grep -m1 -oE 'Verification (SUCCEEDED|FAILED|INCONCLUSIVE)' fm.log`"
