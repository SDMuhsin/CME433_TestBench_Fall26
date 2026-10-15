#!/bin/bash
# Gate-level simulation of dla_fp16_chip on the routed netlist with tb/dla_fp16_chip_tb.sv.
#
# usage (from anywhere; needs iverilog >= 12 on PATH):
#   scripts/run_fp16_gls.sh [nl|pnl] [-- <vvp plusargs>]
#   env: RUN=<librelane run dir>  (default librelane/runs/fp16_final)
#        VVP=<compiled binary>    (default sim/results/dla_fp16_chip_gls_<kind>.vvp; reused if
#                                  newer than netlist + TB, so parallel runs can share one compile)
#        COMPILE_ONLY=1           compile and exit
#   nl  = unpowered final/nl  (zero-delay, gf180mcu_as_sc_mcu7t3v3 cell models + behavioral SRAM)
#   pnl = powered   final/pnl (-DUSE_POWER_PINS)
# Default plusargs: +HALF=2 (SCLK = clk/4). A full image takes ~30 min in Icarus.
# Example (another model / latent):
#   scripts/run_fp16_gls.sh nl -- +WDIR=<dir> +ZQ=<zq.memh> +EXPECTED=<golden.memh> \
#       +CSR_MEMH=<csr.memh> +ACTUAL_MEMH=<pix_out.memh> [+H2Q=<h2q.memh>]
set -o pipefail
cd "$(dirname "$0")/.."
KIND=nl
if [ $# -gt 0 ] && [ "$1" != "--" ]; then KIND=$1; shift; fi
[ "${1:-}" = "--" ] && shift
case $KIND in nl) DEF="" ;; pnl) DEF="-DUSE_POWER_PINS" ;; *) echo "kind must be nl or pnl"; exit 2 ;; esac
RUN=${RUN:-librelane/runs/fp16_final}
NL=${NL:-$RUN/final/$KIND/dla_fp16_chip.$KIND.v}
AS=3V3lib/gf180mcu_as_sc_mcu7t3v3-main/pdk/libs.ref/gf180mcu_as_sc_mcu7t3v3/verilog/gf180mcu_as_sc_mcu7t3v3.v
SRAM=rtl/gf180_sram_1rw_256x8.v
TB=tb/dla_fp16_chip_tb.sv
VVP=${VVP:-sim/results/dla_fp16_chip_gls_$KIND.vvp}
for f in "$NL" "$AS" "$SRAM" "$TB"; do [ -f "$f" ] || { echo "missing $f"; exit 2; }; done
mkdir -p "$(dirname "$VVP")"
echo "netlist: $NL sha256 $(sha256sum "$NL" | cut -c1-16)"
if [ ! -f "$VVP" ] || [ "$NL" -nt "$VVP" ] || [ "$TB" -nt "$VVP" ] || [ "$SRAM" -nt "$VVP" ]; then
    t0=$(date +%s)
    iverilog -g2012 -I rtl -DGLS $DEF -s dla_fp16_chip_tb -o "$VVP" "$NL" "$SRAM" "$AS" "$TB" \
        || { echo COMPILE_FAIL; exit 1; }
    echo "compiled $VVP in $(( $(date +%s) - t0 ))s"
fi
[ -n "${COMPILE_ONLY:-}" ] && exit 0
t0=$(date +%s)
LOG=$(mktemp)
vvp -n "$VVP" "$@" +HALF=2 | tee "$LOG"
grep -q "^PASS:" "$LOG"; rc=$?; rm -f "$LOG"
echo "GLS $KIND: $([ $rc = 0 ] && echo PASS || echo FAIL) in $(( $(date +%s) - t0 ))s"
exit $rc
