#!/usr/bin/env bash
# Activity-based power of the routed mb_chip (OpenSTA report_power + SPEF), from the switching
# activity of the SDF-annotated GLS of one full token (glitches included).
#
#   src/flow/power/run_power.sh [corner ...]   default nom_tt_025C_3v30 nom_ff_n40C_3v60 nom_ss_125C_3v00
#   env: RUN=<run dir>   default src/flow/runs/mb_final
#        SKIP_SIM=1      reuse the GLS runs/VCDs already in src/flow/build/sdf_gls/<corner>_power
#        KEEP_VCD=1      keep the ~5 GB VCDs (default: deleted after the SAIF is written)
#        ZERO_DELAY=0    skip the zero-delay (glitch-free) reference at nom_tt
# Per corner: run_sdf_gls.sh <corner> with the 2-token story "On" (STATE_RESET, 'O', 'n'), VCD of
# the mb_chip nets from START of token 1 to the end of its logit readback -> activity/vcd2saif.py
# (per-pin SAIF) -> report/power.tcl with the SAIF, vectorless, and SAIF + flop proxy
# (report/proxy_lib.py).
# Results: src/flow/build/power/{power,power_sram,power_flops,activity}.<corner>.<tag>.rpt,
# summary.rpt (report/power_summary.py, incl. the SRAM access-count check and energy/token).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
FLOW=$(dirname "$HERE")
SRC=$(dirname "$FLOW")
ROOT=$(dirname "$SRC")
RUN=${RUN:-$FLOW/runs/mb_final}
CORNERS=${*:-nom_tt_025C_3v30 nom_ff_n40C_3v60 nom_ss_125C_3v00}
OUT=$FLOW/build/power
GLS=$FLOW/build/sdf_gls
mkdir -p "$OUT" "$GLS/logs"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3
VEC=$GLS/vec_power_On
if [ ! -s "$VEC/plan.memh" ]; then
    (cd "$ROOT" && $PY -m src.golden.host.vectors src/golden/params/mamba_e96_fp16.npz "$VEC" --story "On") || exit 1
fi
NL=$RUN/final/nl/mb_chip.nl.v

# 1. GLS with VCD (corners in parallel; SDFs first, so parallel runs do not race on the cache)
sims=()
for c in $CORNERS; do sims+=("$c:power:"); done
[ "${ZERO_DELAY:-1}" != 0 ] && sims+=("nom_tt_025C_3v30:power_zd:1")
if [ -z "${SKIP_SIM:-}" ]; then
    mkdir -p "$GLS/sdf"
    for c in $CORNERS; do
        [ -s "$GLS/sdf/mb_chip.$c.sdf" ] && [ "$GLS/sdf/mb_chip.$c.sdf" -nt "$NL" ] && continue
        RUN=$RUN CORNER=$c OUT=$GLS/sdf sta -no_splash -exit "$FLOW/sdf_gls/sdf/write_sdf.tcl" \
            > "$GLS/sdf/sta.$c.log" 2>&1 || { echo "STA failed for $c"; exit 1; }
    done
    pids=()
    for s in "${sims[@]}"; do
        IFS=: read -r c tag zd <<< "$s"
        RUN=$RUN VEC=$VEC VCD_TOK=1 TAG=$tag NOSDF=$zd "$FLOW/sdf_gls/run_sdf_gls.sh" "$c" \
            > "$GLS/logs/${tag}_$c.log" 2>&1 &
        pids+=($!)
    done
    rc=0
    for p in "${pids[@]}"; do wait "$p" || rc=1; done
    [ $rc = 0 ] || { echo "a GLS power run failed (see $GLS/logs/power*_*.log)"; exit 1; }
fi

power() {   # corner tag saif proxy
    local c=$1 tag=$2 saif=$3 proxy=$4
    RUN=$RUN CORNER=$c OUT=$OUT TAG=$c.$tag SAIF=$saif PROXY_LIB=$proxy \
        sta -no_splash -exit "$HERE/report/power.tcl" > "$OUT/sta.$c.$tag.log" 2>&1 ||
        { echo "STA power failed: $OUT/sta.$c.$tag.log"; return 1; }
}
# 2. VCD -> per-pin SAIF (all runs in parallel)
pids=()
for s in "${sims[@]}"; do
    IFS=: read -r c tag zd <<< "$s"
    B=$GLS/${c}_$tag
    grep -q '^PASS' "$B/gls.log" || { echo "GLS $B did not pass"; exit 1; }
    read -r t0 t1 < <(sed -nE 's/^VCD: window ([0-9.]+) \.\. ([0-9.]+) ns.*/\1 \2/p' "$B/gls.log")
    SAIF=$OUT/$c.$tag.saif
    if [ -s "$B/activity.vcd" ]; then
        ( $PY "$HERE/activity/vcd2saif.py" "$B/activity.vcd" "$NL" "$SAIF" \
              --start-ps "$(awk -v t="$t0" 'BEGIN { printf "%.0f", t * 1000 }')" \
              --end-ps "$(awk -v t="$t1" 'BEGIN { printf "%.0f", t * 1000 }')" > "$OUT/vcd2saif.$c.$tag.log" &&
          { [ -n "${KEEP_VCD:-}" ] || rm -f "$B/activity.vcd"; } ) &
        pids+=($!)
    fi
done
rc=0
for p in "${pids[@]}"; do wait "$p" || rc=1; done
[ $rc = 0 ] || { echo "vcd2saif failed (see $OUT/vcd2saif.*.log)"; exit 1; }
cat "$OUT"/vcd2saif.*.log

# 3. power: SAIF, vectorless, SAIF + flop proxy; zero-delay SAIF at nom_tt
for s in "${sims[@]}"; do
    IFS=: read -r c tag zd <<< "$s"
    SAIF=$OUT/$c.$tag.saif
    [ -s "$SAIF" ] || { echo "no SAIF $SAIF"; exit 1; }
    pvt=${c#*_}
    if [ -n "$zd" ]; then
        power "$c" zero_delay "$SAIF" "" || exit 1
    else
        $PY "$HERE/report/proxy_lib.py" "$PDK_ROOT/gf180mcuD/libs.ref/gf180mcu_fd_sc_mcu7t5v0/lib/gf180mcu_fd_sc_mcu7t5v0__$pvt.lib" \
            "$OUT/proxy_$pvt.lib" >/dev/null || exit 1
        power "$c" saif "$SAIF" "" &
        power "$c" vectorless "" "" &
        power "$c" saif_proxy "$SAIF" "$OUT/proxy_$pvt.lib" &
        wait
    fi
done
# shellcheck disable=SC2086
$PY "$HERE/report/power_summary.py" "$OUT" "$GLS" $CORNERS
