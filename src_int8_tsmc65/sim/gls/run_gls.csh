#!/bin/tcsh -f
# Zero-delay gate-level simulation of a DC netlist with the unchanged src_int8 chip TB (VCS),
# SAIF of one token for PrimePower:  sim/gls/run_gls.csh <syn_tag> <vec_name> [timescale=100ps] [saif_tok=1]
#   netlist  $MQ65/build/syn/<syn_tag>/mq_chip.v      vectors $MQ65/build/gls/vec/<vec_name>/
#   timescale: the TB clock is "#20" per half period, so 100ps/1ps runs it at 4 ns (250 MHz);
#              1ns/1ps is the TB's own 40 ns (25 MHz)
#   saif_tok: TB token index whose run_token() window is recorded (sim/gls/gls_saif.sv)
#   output: $MQ65/build/gls/<syn_tag>_<vec_name>[_t<saif_tok> if not 1]/ (tb.log, mq_chip.saif)
setenv MQ65 `cd $0:h/../.. && pwd`
source $MQ65/syn/common/env.csh
set SRC = $MQ65:h/src_int8
set ts = 100ps
if ($#argv >= 3) set ts = $3
set tok = 1
if ($#argv >= 4) set tok = $4
set out = $MQ65/build/gls/$1_$2
if ($tok != 1) set out = ${out}_t$tok
set vec = $MQ65/build/gls/vec/$2
set vlog = $MQ65_VLOG
mkdir -p $out
cd $out
vcs -full64 -sverilog -override_timescale=$ts/1ps +delay_mode_zero +nospecify +notimingcheck \
    +lint=none -j8 +incdir+$SRC/tb/common -v $vlog -top tb_mq_chip -top gls_saif \
    $MQ65/build/syn/$1/mq_chip.v $SRC/tb/chip/tb_mq_chip.sv $MQ65/sim/gls/gls_saif.sv \
    -o simv >& compile.log
if (! -x simv) then
    echo "GLS_DONE $out:t compile FAILED (compile.log)"; exit 1
endif
./simv +VEC=$vec +SAIF=$out/mq_chip.saif +GLS_TOK=$tok >& tb.log
echo "GLS_DONE $out:t `grep -E '^(PASS|FAIL)' tb.log | head -1`"
