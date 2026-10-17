#!/bin/tcsh -f
# Zero-delay gate-level simulation of a gan65 DC netlist with the benchmark TB (VCS):
#   sim/gls/run_gls.csh <syn_tag> [seed=0] [clk_period_ns=40] [saif=0]
#   netlist  $GAN65/build/syn/<syn_tag>/gan65_chip.v
#   image    model/fmnist/ref_vectors/seed_<seed>: zq.memh in, expected.memh = golden pixels
#            (exact multiplier; for a variant the comparison only says whether it is exact)
#   state    every register / latch starts at 0 (+vcs+initreg+0): the RTL is verified in
#            2-state Verilator, and some datapath registers have no reset;
#            GAN65_GLS_INIT=random starts them at random values instead (output dir suffix _rnd)
#   period   TB clock (CLK_HALF_NS = period / 2); set the synthesis clock for SAIF
#   saif=1   also write gan65_chip.saif (first image, START .. STATUS, sim/gls/gls_saif.sv)
#   GAN65_GLS_SDF=<corner>  timing-annotated run instead of zero delay: SDF of that corner
#            (sim/gls/run_sdf.csh, written if missing; ideal root clock), output suffix _sdf<corner>;
#            the SAIF then counts glitch transitions (inertial cell delays, no timing checks)
#   output: $GAN65/build/gls/<syn_tag>_s<seed>/ (compile.log, tb.log, pix.memh, gan65_chip.saif)
setenv GAN65 `cd $0:h/../.. && pwd`
source $GAN65/syn/common/env.csh
set seed = 0
if ($#argv >= 2) set seed = $2
set period = 40
if ($#argv >= 3) set period = $3
set saif = 0
if ($#argv >= 4) set saif = $4
set half = `echo "$period" | awk '{print $1 / 2}'`
set net = $GAN65/build/syn/$1/gan65_chip.v
set out = $GAN65/build/gls/$1_s$seed
set model = $GAN65/model/fmnist
set ref = $model/ref_vectors/seed_$seed
set init = 0
if ($?GAN65_GLS_INIT) then
    set init = $GAN65_GLS_INIT
endif
if ($init != 0) set out = ${out}_rnd
set dly = "+delay_mode_zero +nospecify"
set act = "SAIF from zero-delay GLS (no glitches)"
if ($?GAN65_GLS_SDF) then
    set sdf = $GAN65/build/syn/$1/gan65_chip.$GAN65_GLS_SDF.sdf
    if (! -s $sdf) $GAN65/sim/gls/run_sdf.csh $1 $GAN65_GLS_SDF $period
    set dly = "-sdf max:gan65_bench_tb.dut:$sdf"
    set act = "SAIF from SDF-timed GLS ($GAN65_GLS_SDF corner, glitches counted)"
    set out = ${out}_sdf$GAN65_GLS_SDF
endif
mkdir -p $out
cd $out
echo "$act" > activity
vcs -full64 -sverilog -timescale=1ns/1ps $dly +notimingcheck +lint=none -j8 +vcs+initreg+random \
    -pvalue+gan65_bench_tb.CLK_HALF_NS=$half -v $MQ65_VLOG -top gan65_bench_tb -top gls_saif \
    $net $GAN65/bench/tb/gan65_bench_tb.sv $GAN65/sim/gls/gls_saif.sv -o simv >& compile.log
if (! -x simv) then
    echo "GLS_DONE $out:t compile FAILED (compile.log)"; exit 1
endif
set sp = ""
if ($saif == 1) set sp = "+SAIF=$out/gan65_chip.saif"
./simv +vcs+initreg+$init +WDIR=$model +CSR_MEMH=$model/csr.memh +ZQ_ALL=$ref/zq.memh +OUT=$out/pix.memh $sp >& tb.log
set res = FAIL
cmp -s $out/pix.memh $ref/expected.memh
if ($status == 0) set res = PASS
echo "GLS_DONE $out:t $res (pixels vs golden seed_$seed) `grep -E '^(DONE|FAIL|IMAGE)' tb.log | tr '\n' ' '`"
