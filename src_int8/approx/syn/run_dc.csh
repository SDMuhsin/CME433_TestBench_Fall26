#!/bin/tcsh -f
# Standalone DC run of one mq_mul8 variant on the server (65 nm, site config of src_int8_tsmc65):
#   src_int8/approx/syn/run_dc.csh <variant> <corner> <max_delay_ns> [NAME=VALUE ...]
#     <variant>  exact (src_int8/rtl/int/mq_mul8.v) | <name> (src_int8/bench/variants/<name>.v or <name>/)
#     NAME=VALUE `define overrides of a configurable variant (e.g. CSSM_M=4)
#   output: <repo>/build/approx/syn/<tag>/, summary -> <repo>/build/approx/summary/syn_<tag>.txt
#   tag = <variant>[_<NAME><VALUE>...]_<corner>_d<max_delay_ns>
set APX = `cd $0:h/.. && pwd`
set SRC = $APX:h
set REPO = $SRC:h
setenv MQ65 $REPO/src_int8_tsmc65
source $MQ65/syn/common/env.csh
set v = $1
if ("$v" == "exact") then
    set srcs = "$SRC/rtl/int/mq_mul8.v"
else if (-f $SRC/bench/variants/$v.v) then
    set srcs = "$SRC/bench/variants/$v.v"
else if (-d $SRC/bench/variants/$v) then
    set srcs = "`ls $SRC/bench/variants/$v/*.v`"
else
    echo "unknown variant $v"; exit 1
endif
set tag = $v
set defs = ""
foreach d ($argv[4-])
    set defs = "$defs $d"
    set tag = ${tag}_`echo $d | tr -d =`
end
set tag = ${tag}_$2_d$3
setenv MUL8_SRC "$srcs"
setenv MUL8_DEFS "$defs"
setenv MUL8_CORNER $2
setenv MUL8_DELAY $3
setenv MUL8_OUT $REPO/build/approx/syn/$tag
mkdir -p $MUL8_OUT $REPO/build/approx/summary
cd $MUL8_OUT
dc_shell -f $APX/syn/dc_mul8.tcl >& dc.log
if (-f summary.txt) cp -f summary.txt $REPO/build/approx/summary/syn_$tag.txt
echo "DC_DONE $tag errors `grep -c '^Error' dc.log`"
