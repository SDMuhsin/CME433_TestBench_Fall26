#!/usr/bin/env bash
# Abort / reset path test of mb_chip (src/tb/abort/tb_mb_abort.sv; spec section 7.1).
#   src/tb/run_abort.sh [verilator|iverilog|all] [build_dir] [-- +SEED=n +NRAND=n ...]
# verilator (default): 2-state, all uninitialised flops / SRAM randomised (--x-initial unique,
#   seed = SEED), ~2 min.  iverilog: 4-state, adds the X / Z checks on every chip output, ~1.4 h.
# Needs a python3 with numpy (PYTHON=..., else /usr/bin/python3); Verilator: $VERILATOR, else
# `verilator` on PATH, else the first Verilator 5 in /nix/store.
# Prints one line per scenario, the abort coverage and PASS/FAIL; exit 0 only if all PASS.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
MODE=verilator
case "${1:-}" in verilator|iverilog|all) MODE=$1; shift;; esac
BUILD=$SRC/tb/build
if [ $# -gt 0 ] && [ "$1" != "--" ]; then mkdir -p "$1" && BUILD=$(cd "$1" && pwd); shift; fi
[ "${1:-}" = "--" ] && shift
ARGS=("$@")
SEED=1
for a in "${ARGS[@]}"; do case $a in +SEED=*) SEED=${a#+SEED=};; esac; done
mkdir -p "$BUILD"
cd "$ROOT"
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3

VEC=$BUILD/abort_vec
$PY -m src.tb.abort.gen_vectors src/golden/params/mamba_e96_fp16.npz "$VEC" || exit 1
RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f")
INC=(-I"$SRC/rtl/nonlin" -I"$SRC/rtl/seq" -I"$SRC/tb/chip" -I"$SRC/tb/abort/inc")
TB="$SRC/rtl/mem/gf180_sram_macro.v $SRC/tb/abort/tb_mb_abort.sv"
rc=0

run_one() {   # name, command...
    local name=$1; shift
    local log=$BUILD/tb_mb_abort.$name.seed$SEED.log
    "$@" "+VEC=$VEC" "${ARGS[@]}" >"$log" 2>&1
    grep -E '^(SCEN .*FAIL|FAIL|PASS|ABORT|X CHECK|  [a-zA-Z_]+ +[0-9]+  act|                   sec)' "$log" |
        sed "s/^/[$name] /"
    grep -q '^PASS' "$log" || { echo "[$name] FAIL (log: $log)"; rc=1; }
}

if [ "$MODE" = verilator ] || [ "$MODE" = all ]; then
    VL=${VERILATOR:-$(command -v verilator || ls -d /nix/store/*-verilator-5*/bin/verilator 2>/dev/null | head -1)}
    [ -x "$VL" ] || { echo "FAIL: no verilator found (set VERILATOR=...)"; exit 1; }
    OUT=$BUILD/abort_vl
    mkdir -p "$OUT"
    BIN=$OUT/tb_mb_abort
    # rebuild only if an RTL / TB source is newer than the binary (the build takes ~10 min)
    STALE=yes
    [ -x "$BIN" ] && [ -z "$(find "$SRC/rtl" "$SRC/tb/abort" "$SRC/tb/chip" -newer "$BIN" \
        \( -name '*.v' -o -name '*.vh' -o -name '*.sv' -o -name '*.svh' \) | head -1)" ] && STALE=
    if [ -n "$STALE" ]; then
        "$VL" --binary --timing -j 16 -Wno-fatal -Wno-lint -Wno-style --x-assign unique --x-initial unique \
            "${INC[@]}" --top-module tb_mb_abort -Mdir "$OUT/obj" -o "$BIN" -CFLAGS -O2 \
            $RTL $TB >"$OUT/build.log" 2>&1 ||
            { echo "FAIL: verilator build (see $OUT/build.log)"; exit 1; }
    fi
    run_one verilator "$BIN" "+verilator+seed+$SEED" +verilator+rand+reset+2
fi
if [ "$MODE" = iverilog ] || [ "$MODE" = all ]; then
    VVP=$BUILD/tb_mb_abort.vvp
    iverilog -g2012 -Wall "${INC[@]}" -s tb_mb_abort -o "$VVP" $RTL $TB 2>"$BUILD/tb_mb_abort.compile.log" ||
        { echo "FAIL: iverilog compile (see $BUILD/tb_mb_abort.compile.log)"; exit 1; }
    run_one iverilog vvp -n "$VVP"
fi
exit $rc
