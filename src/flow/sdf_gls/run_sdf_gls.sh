#!/usr/bin/env bash
# Timing-annotated gate-level simulation of the routed mb_chip (SDF back-annotation, active
# $setuphold/$width/$period/$setup/$hold/$recrem checks), Open Source CVC (tools/setup_cvc.sh).
#
#   src/flow/sdf_gls/run_sdf_gls.sh <corner> [-- <src.golden.host.vectors args, e.g. --story "Once">]
#     corner: one of the 9 signoff corners, e.g. min_ff_n40C_3v60 / nom_tt_025C_3v30 /
#             max_ss_125C_3v00.  min_* uses the SDF min values (+mindelays), nom_* typ, max_* max.
#   env: RUN=<run dir>     default src/flow/runs/mb_final
#        KIND=nl|pnl        unpowered (default) or powered netlist
#        VEC=<dir>          existing vectors (plan/stream/logits.memh); default: generated from the
#                           vector args (default = the 31-token chip-TB set)
#        NTOK=n MAXCYC=n PROGRESS=n VCD_TOK=t   TB plusargs (VCD -> <build>/activity.vcd)
#        TCLK=<ns>          clock period (default 40; negative setup test)
#        SKEW="<inst.pin>=<ns> ..."   add delay to the INTERCONNECTs into these pins (negative test)
#        PROBE="setup|hold <P ns>"    margin probe (checks/margin_probe.py), not a pass/fail run
#        NOSDF=1            zero-delay reference run (no SDF, +nospecify, glitch-free activity
#                           for the power comparison) with the zero-delay SRAM model models/sram_zd.v
#        TAG=<name>         build dir suffix: src/flow/build/sdf_gls/<corner>[_<TAG>]
# Steps (sub-dirs of src/flow/sdf_gls): model self-test (checks/model_selftest) -> cell models (models/gen_cells.py) -> netlist copy
# (sdf/legal_netlist.py) -> signoff STA + SDF of the corner (sdf/write_sdf.tcl) -> SDF fix-ups
# (sdf/fix_sdf.py) [-> sdf/skew_sdf.py / checks/margin_probe.py edits] -> CVC (tools/setup_cvc.sh)
# compile with +sdf_annotate -> annotation coverage (checks/sdf_coverage.py, must be 100 %) -> sim.
# Prints a RESULT line; exit 0 only for a bit-exact PASS with 0 timing-check violations, 0 SRAM
# model errors, 0 output-timing violations and 100 % SDF coverage (probe runs: exit 0 if it ran).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FLOW=$(dirname "$HERE")
SRC=$(dirname "$FLOW")
ROOT=$(dirname "$SRC")
CORNER=${1:?corner}; shift
[ "${1:-}" = "--" ] && shift
case $CORNER in
    min_*) SEL=+mindelays ;; nom_*) SEL=+typdelays ;; max_*) SEL=+maxdelays ;;
    *) echo "bad corner $CORNER"; exit 2 ;;
esac
PVT=${CORNER#*_}
RUN=${RUN:-$FLOW/runs/mb_final}
[ -n "${VEC:-}" ] && { VEC=$(cd "$VEC" && pwd) || exit 2; }
KIND=${KIND:-nl}
TOP=$FLOW/build/sdf_gls
BUILD=$TOP/$CORNER${TAG:+_$TAG}
mkdir -p "$BUILD" "$TOP/sdf"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3
PDKLIB=$PDK_ROOT/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3
LIB_TT=$PDKLIB/lib/gf180mcu_as_sc_mcu7t3v3__tt_025C_3v30.lib
LIB=$PDKLIB/lib/gf180mcu_as_sc_mcu7t3v3__$PVT.lib
AS_V=$ROOT/3V3lib/gf180mcu_as_sc_mcu7t3v3-main/pdk/libs.ref/gf180mcu_as_sc_mcu7t3v3/verilog/gf180mcu_as_sc_mcu7t3v3.v
NL=$RUN/final/$KIND/mb_chip.$KIND.v
for f in "$NL" "$LIB" "$AS_V"; do [ -f "$f" ] || { echo "missing $f"; exit 2; }; done

CVC=$("$HERE/tools/setup_cvc.sh") || exit 2
# 0. simulator/model self-test (the CVC behaviours the models rely on)
"$HERE/checks/model_selftest/run.sh" "$BUILD/selftest" | tail -n 1 | tee "$BUILD/selftest.log"
grep -q '^SELFTEST PASS' "$BUILD/selftest.log" || exit 1
cd "$HERE"
# 1. cell models (function from the library .v, arcs/checks from the tt Liberty: same in all
#    corners); per build dir, so parallel runs do not share generated files
$PY models/gen_cells.py "$LIB_TT" "$AS_V" "$BUILD/cells.v" >/dev/null || exit 1
# 2. netlist with legal SRAM instance names
$PY sdf/legal_netlist.py "$NL" "$BUILD/mb_chip.$KIND.v" >/dev/null || exit 1
# 3. signoff STA + SDF of the corner (cached per run/corner in $TOP/sdf: generate it once before
#    starting several runs of the same corner in parallel)
SDF=$TOP/sdf/mb_chip.$CORNER.sdf
if [ ! -s "$SDF" ] || [ "$NL" -nt "$SDF" ] || [ "$HERE/sdf/write_sdf.tcl" -nt "$SDF" ]; then
    RUN=$RUN CORNER=$CORNER OUT=$TOP/sdf sta -no_splash -exit "$HERE/sdf/write_sdf.tcl" \
        >"$TOP/sdf/sta.$CORNER.log" 2>&1 || { echo "STA_FAIL (see $TOP/sdf/sta.$CORNER.log)"; exit 1; }
fi
# 4. SDF fix-ups (+ optional negative-test skew / margin probe)
FIXED=$BUILD/mb_chip.$CORNER.sdf
$PY sdf/fix_sdf.py "$SDF" "$TOP/sdf/arcs.$CORNER.rpt" "$LIB" "$FIXED" >"$BUILD/fix_sdf.log" || exit 1
DEFS=""
if [ -n "${SKEW:-}" ]; then
    # shellcheck disable=SC2086
    $PY sdf/skew_sdf.py "$FIXED" "$FIXED.skew" $SKEW | tee "$BUILD/skew.log" || exit 1
    mv "$FIXED.skew" "$FIXED"
fi
if [ -n "${PROBE:-}" ]; then
    read -r PKIND PVAL <<< "$PROBE"
    $PY checks/margin_probe.py make "$FIXED" "$FIXED.probe" "$PKIND" "$PVAL" | tee "$BUILD/probe.log" || exit 1
    mv "$FIXED.probe" "$FIXED"
    DEFS="+define+MB_TCHK_PROBE"
fi
[ "$KIND" = pnl ] && DEFS="$DEFS +define+USE_POWER_PINS"
[ -n "${TCLK:-}" ] && DEFS="$DEFS +define+TCLK=$TCLK"

# 5. vectors
if [ -z "${VEC:-}" ]; then
    VEC=$BUILD/chip_vec
    (cd "$ROOT" && $PY -m src.golden.host.vectors src/golden/params/mamba_e96_fp16.npz "$VEC" "$@") || exit 1
fi

# 6. compile (SDF annotation messages -> sdf_compile.log)
cd "$BUILD"
SIM=$BUILD/sim
t0=$(date +%s)
SRAM_V=$HERE/models/sram_sdf.v
if [ -n "${NOSDF:-}" ]; then
    ANNO="+nospecify"     # no path delays, no timing checks
    SRAM_V=$HERE/models/sram_zd.v
else
    ANNO="+sdf_annotate $FIXED+tb_mb_chip_sdf.dut +sdfverbose +sdf_log_file $BUILD/sdf.log"
fi
# CVC writes fixed-name /tmp/cvclib.o, /tmp/exe_main.o while linking: one compile at a time
# shellcheck disable=SC2086
flock "$TOP/.cvc_compile.lock" "$CVC" $SEL $DEFS +suppress_warns+531+ $ANNO +incdir+"$SRC/tb/sdf" -o "$SIM" \
    "$BUILD/mb_chip.$KIND.v" -v "$BUILD/cells.v" -v "$SRAM_V" "$SRC/tb/sdf/tb_mb_chip_sdf.v" \
    >"$BUILD/compile.log" 2>&1 && [ -x "$SIM" ] || { echo "COMPILE_FAIL (see $BUILD/compile.log)"; exit 1; }
[ -z "${NOSDF:-}" ] && cp "$BUILD/sdf.log" "$BUILD/sdf_compile.log"
echo "compiled $SIM in $(( $(date +%s) - t0 ))s ($SEL $DEFS)"

# 7. annotation coverage
if [ -n "${NOSDF:-}" ]; then
    echo "NOSDF: zero-delay run, no annotation, timing checks off" > "$BUILD/coverage.rpt"; COV=0
else
$PY "$HERE/checks/sdf_coverage.py" "$FIXED" "$BUILD/sdf_compile.log" "$BUILD/mb_chip.$KIND.v" "$BUILD/cells.v" \
    "$HERE/models/sram_sdf.v" "$BUILD/coverage.rpt" >/dev/null
COV=$?
fi
grep -E '^(TOTAL|instances|model timing|SDF_COVERAGE|NOSDF)' "$BUILD/coverage.rpt"

# 8. simulate
ARGS="+PLAN=$VEC/plan.memh +STREAM=$VEC/stream.memh +LOGITS=$VEC/logits.memh"
[ -n "${NTOK:-}" ] && ARGS="$ARGS +NTOK=$NTOK"
[ -n "${MAXCYC:-}" ] && ARGS="$ARGS +MAXCYC=$MAXCYC"
[ -n "${PROGRESS:-}" ] && ARGS="$ARGS +PROGRESS=$PROGRESS"
[ -n "${VCD_TOK:-}" ] && ARGS="$ARGS +VCD_TOK=$VCD_TOK +VCD=$BUILD/activity.vcd"
LOG=$BUILD/gls.log
t0=$(date +%s)
if [ -n "${PROBE:-}" ]; then
    # shellcheck disable=SC2086
    "$SIM" $ARGS 2>&1 | $PY "$HERE/checks/margin_probe.py" reduce $PROBE "$BUILD/margin.rpt" > "$LOG"
else
    # shellcheck disable=SC2086
    "$SIM" $ARGS > "$LOG" 2>&1
fi
SECS=$(( $(date +%s) - t0 ))
# the runtime re-annotation must match the compile-time one
[ -n "${NOSDF:-}" ] || cmp -s "$BUILD/sdf.log" "$BUILD/sdf_compile.log" || echo "note: runtime SDF log differs from compile-time log"

# 9. verdict
grep -E '^(vectors|TOKEN|CYCLES|IO:|PASS|FAIL|STOP|SRAM|VCD)' "$LOG"
NVIOL=$(grep -c '\[566\] timing violation' "$LOG")
NSRAM=$(grep -c -- '---- ERROR:' "$LOG")
NIO=$(grep -c '^IO-TIMING' "$LOG")
{
    echo "corner $CORNER kind $KIND sel $SEL defs [$DEFS] tclk ${TCLK:-40} skew [${SKEW:-}] probe [${PROBE:-}] nosdf [${NOSDF:-}]"
    echo "sim wall ${SECS}s"
    echo "timing-check violations ([566] reports): $NVIOL"
    grep '\[566\] timing violation' "$LOG" | sed -E 's/.*WARN\*\* now [0-9]+ ps \[566\] timing violation in ([^ ]+) .*/\1/' |
        sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
    grep -A1 '\[566\] timing violation' "$LOG" | grep -vE 'timing violation|^--' |
        sed -E 's/[0-9]+ ps//g; s/^ +//' | sort | uniq -c | sort -rn | head -10 | sed 's/^/  /'
    echo "SRAM model error messages: $NSRAM"
    echo "output-timing violations: $NIO"
} > "$BUILD/timing.rpt"
sed -n 2,3p "$BUILD/timing.rpt"
if [ -n "${PROBE:-}" ]; then
    tail -n 1 "$BUILD/margin.rpt"
    echo "RESULT $CORNER${TAG:+_$TAG}: PROBE done in ${SECS}s (margin.rpt)"
    exit 0
fi
if grep -q '^PASS' "$LOG" && [ "$NVIOL" = 0 ] && [ "$NSRAM" = 0 ] && [ "$NIO" = 0 ] && [ $COV = 0 ]; then
    if [ -n "${NOSDF:-}" ]; then
        echo "RESULT $CORNER${TAG:+_$TAG}: PASS zero-delay ($(grep -c '^TOKEN' "$LOG") tokens bit-exact, no SDF, timing checks off) in ${SECS}s"
    else
        echo "RESULT $CORNER${TAG:+_$TAG}: PASS ($(grep -c '^TOKEN' "$LOG") tokens bit-exact, 0 timing violations, SDF coverage 100 %) in ${SECS}s"
    fi
    exit 0
fi
echo "RESULT $CORNER${TAG:+_$TAG}: FAIL (TB $(grep -qE '^PASS' "$LOG" && echo PASS || echo FAIL), $NVIOL timing violations, $NSRAM SRAM errors, $NIO IO-timing, coverage rc $COV) in ${SECS}s"
exit 1
