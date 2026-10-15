#!/usr/bin/env bash
# Gate-level simulation of the routed mb_chip netlist with the chip TB (src/tb/chip/tb_mb_chip.sv);
# mirrors scripts/run_fp16_gls.sh (zero-delay, Icarus, gf180mcu_as_sc_mcu7t3v3 cell models +
# behavioural SRAM model src/rtl/mem/gf180_sram_macro.v).
#
#   src/flow/gls/run_gls.sh [nl|pnl] [-- <src.golden.host.vectors args, e.g. --story "Once upon">]
#   env: RUN=<run dir>        default src/flow/runs/mb_final
#        VEC=<vector dir>     reuse existing vectors (plan/stream/logits.memh) instead of generating
#        BUILD=<dir>          default src/flow/build/gls_<kind>  (vvp, vectors, log)
#        COMPILE_ONLY=1       compile and exit
#   nl  = unpowered final/nl/mb_chip.nl.v
#   pnl = powered   final/pnl/mb_chip.pnl.v (-DUSE_POWER_PINS)
# Default vectors = the RTL chip TB set (2 stories, 31 tokens, state reset between them).
# Prints PASS/FAIL; exit 0 only if every logit of every token is bit-exact vs src/golden.
set -uo pipefail
FLOW=$(cd "$(dirname "$0")/.." && pwd)
SRC=$(dirname "$FLOW")
ROOT=$(dirname "$SRC")
KIND=nl
if [ $# -gt 0 ] && [ "$1" != "--" ]; then KIND=$1; shift; fi
[ "${1:-}" = "--" ] && shift
case $KIND in nl) DEF="" ;; pnl) DEF="-DUSE_POWER_PINS" ;; *) echo "kind must be nl or pnl"; exit 2 ;; esac
RUN=${RUN:-$FLOW/runs/mb_final}
NL=$RUN/final/$KIND/mb_chip.$KIND.v
AS=$ROOT/3V3lib/gf180mcu_as_sc_mcu7t3v3-main/pdk/libs.ref/gf180mcu_as_sc_mcu7t3v3/verilog/gf180mcu_as_sc_mcu7t3v3.v
SRAM=$SRC/rtl/mem/gf180_sram_macro.v
TB=$SRC/tb/chip/tb_mb_chip.sv
BUILD=${BUILD:-$FLOW/build/gls_$KIND}
for f in "$NL" "$AS" "$SRAM" "$TB"; do [ -f "$f" ] || { echo "missing $f"; exit 2; }; done
mkdir -p "$BUILD"
cd "$ROOT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3

IVL=$(command -v iverilog) || { echo "iverilog not on PATH"; exit 2; }
VVPBIN=$(dirname "$IVL")/vvp          # the runtime must match the compiler version
echo "netlist: $NL sha256 $(sha256sum "$NL" | cut -c1-16)"
VVP=$BUILD/tb_mb_chip_gls.vvp
if [ ! -f "$VVP" ] || [ "$NL" -nt "$VVP" ] || [ "$TB" -nt "$VVP" ] || [ "$SRAM" -nt "$VVP" ]; then
    t0=$(date +%s)
    "$IVL" -g2012 -DGLS $DEF -I "$SRC/tb/chip" -s tb_mb_chip -o "$VVP" \
        "$NL" "$SRAM" "$AS" "$TB" 2>"$BUILD/compile.log" ||
        { echo "COMPILE_FAIL (see $BUILD/compile.log)"; exit 1; }
    echo "compiled $VVP in $(( $(date +%s) - t0 ))s"
fi
[ -n "${COMPILE_ONLY:-}" ] && exit 0

if [ -z "${VEC:-}" ]; then
    VEC=$BUILD/chip_vec
    $PY -m src.golden.host.vectors src/golden/params/mamba_e96_fp16.npz "$VEC" "$@" || exit 1
fi
LOG=$BUILD/gls.log
t0=$(date +%s)
"$VVPBIN" -n "$VVP" "+VEC=$VEC" | tee "$LOG" | grep -E '^(vectors|TOKEN|CYCLES|PASS|FAIL)'
grep -q '^PASS' "$LOG"; rc=$?
echo "GLS $KIND: $([ $rc = 0 ] && echo PASS || echo FAIL) in $(( $(date +%s) - t0 ))s (log $LOG)"
exit $rc
