#!/bin/tcsh -f
# Formality run on the server:  lec/run_fm.csh <syn_tag>     (e.g. exact_ss_p2.5)
#   reference RTL and library corner are those of the DC run build/syn/<syn_tag>
#   output: $GAN65/build/lec/<syn_tag>/, summary copied to $GAN65/build/summary/fm_<syn_tag>.txt
setenv GAN65 `cd $0:h/.. && pwd`
source $GAN65/syn/common/env_pt.csh
setenv GAN65_SYN $GAN65/build/syn/$1
setenv GAN65_CORNER `cat $GAN65_SYN/corner`
setenv GAN65_MUL_F $GAN65_SYN/mul.f
setenv GAN65_WIDTH 8
if (-f $GAN65_SYN/width) setenv GAN65_WIDTH `cat $GAN65_SYN/width`
setenv GAN65_TAG fm_$1
setenv GAN65_OUT $GAN65/build/lec/$1
mkdir -p $GAN65_OUT $GAN65/build/summary
cd $GAN65_OUT
fm_shell -f $GAN65/lec/fm_lec.tcl >& fm.log
if (-f summary.txt) cp -f summary.txt $GAN65/build/summary/$GAN65_TAG.txt
echo "FM_DONE $GAN65_TAG errors `grep -c '^Error' fm.log` `grep -m1 -E 'Verification (SUCCEEDED|FAILED|INCONCLUSIVE)' fm.log`"
