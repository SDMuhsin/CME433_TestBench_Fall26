#!/bin/tcsh -f
# Power of a mul_bench netlist on the server, one stimulus set:
#   syn/mulbench/run_power.csh <syn_tag> <uniform|gan> [period_ns=2.5] [count=20000]
# 1. stimulus (stimulus.py; unsigned for designs u_*, signed for all others)
# 2. SDF at tt (write_sdf.tcl, once per netlist) and SDF-timed VCS GLS with SAIF (tb_mul_saif.sv)
# 3. PrimePower tt averaged (pp_mul.tcl)
# Output $GAN65/build/mulbench/<syn_tag>/pwr_<set>/, summary copied to
# $GAN65/build/summary/mbpwr_<syn_tag>_<set>.txt
setenv GAN65 `cd $0:h/../.. && pwd`
source $GAN65/syn/common/env_pt.csh
set tag = $1
set stim = $2
set period = 2.5
if ($#argv >= 3) set period = $3
set count = 20000
if ($#argv >= 4) set count = $4
set n = `echo $tag | sed -E 's/^w([0-9]+)_.*/\1/'`
set sign = signed
if ("`echo $tag | grep -c '^w[0-9]*_u_'`" == 1) set sign = unsigned
set mb = $GAN65/syn/mulbench
setenv MB_SYN $GAN65/build/mulbench/$tag
setenv MB_CORNER tt
setenv MB_RC max
setenv MB_PERIOD $period
setenv MB_SDF $MB_SYN/mul_bench.tt.sdf
set out = $MB_SYN/pwr_$stim
mkdir -p $out $GAN65/build/summary
cd $out
python3 $mb/stimulus.py $n $stim $sign $count stim.memh
if (! -s $MB_SDF) pt_shell -f $mb/write_sdf.tcl >& $MB_SYN/sdf_tt.log
set half = `echo "$period" | awk '{print $1 / 2}'`
vcs -full64 -sverilog -timescale=1ns/1ps -sdf max:tb_mul_saif.dut:$MB_SDF +notimingcheck +lint=none \
    -pvalue+tb_mul_saif.N=$n -pvalue+tb_mul_saif.HALF=$half -v $MQ65_VLOG -top tb_mul_saif \
    $MB_SYN/mul_bench.v $mb/tb_mul_saif.sv -o simv >& compile.log
if (! -x simv) then
    echo "PWR_DONE $tag $stim GLS compile FAILED"; exit 1
endif
./simv +STIM=stim.memh +COUNT=$count +SAIF=$out/mul_bench.saif +OUT=$out/p.memh >& sim.log
setenv MB_SAIF $out/mul_bench.saif
setenv MB_OUT $out
setenv MB_TAG ${tag}_$stim
pt_shell -f $mb/pp_mul.tcl >& pp.log
if (-f summary.txt) cp -f summary.txt $GAN65/build/summary/mbpwr_${tag}_$stim.txt
rm -rf csrc simv.daidir simv
echo "PWR_DONE $tag $stim `grep -m1 SAIF_DONE sim.log` errors `grep -c '^Error' pp.log`"
