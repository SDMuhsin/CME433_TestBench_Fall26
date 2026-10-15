#!/usr/bin/env bash
# Run every datapath unit TB against golden-generated vectors; prints PASS/FAIL per unit.
#   src/tb/run_unit.sh [build_dir]      (default src/tb/build; needs iverilog and a python3
#   with numpy -- set PYTHON=... if the first python3 on PATH has none, e.g. in the nix shell)
# Exit status 0 only if the NLU ROM is up to date and every unit passes.
set -u
SRC=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(dirname "$SRC")
BUILD=${1:-$SRC/tb/build}
mkdir -p "$BUILD/rom"
cd "$ROOT"
fail=0
PY=${PYTHON:-python3}
$PY -c 'import numpy' 2>/dev/null || PY=/usr/bin/python3

$PY -m src.scripts.gen_nlu_rom "$BUILD/rom" &&
    diff -q "$BUILD/rom/mb_nlu_rom.v" src/rtl/nonlin/mb_nlu_rom.v >/dev/null &&
    diff -q "$BUILD/rom/mb_nlu_defs.vh" src/rtl/nonlin/mb_nlu_defs.vh >/dev/null &&
    echo "PASS nlu_rom: generated RTL matches src/golden" ||
    { echo "FAIL nlu_rom: rerun python3 -m src.scripts.gen_nlu_rom"; fail=1; }

$PY -m src.tb.vectors "$BUILD/vec" || exit 1

RTL=$(sed -e '/^\/\//d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/units.f")
for tb in fp16_to_fp32 fpu_mac fp32_wb lane nlu; do
    vvp_out="$BUILD/tb_$tb.vvp"
    if ! iverilog -g2012 -Wall -I "$SRC/rtl/nonlin" -I "$SRC/tb/unit" -s "tb_$tb" -o "$vvp_out" \
            $RTL "$SRC/tb/unit/tb_$tb.sv" 2>"$BUILD/tb_$tb.compile.log"; then
        echo "FAIL $tb: compile error (see $BUILD/tb_$tb.compile.log)"; fail=1; continue
    fi
    out=$(vvp -n "$vvp_out" "+VEC=$BUILD/vec/$tb.hex" | grep -E '^(PASS|FAIL|MISMATCH)')
    echo "$out"
    grep -q '^PASS' <<<"$out" || fail=1
done
exit $fail
