#!/usr/bin/env bash
# Model self-test of the SDF GLS (tb_selftest.v header): generated cell models + models/sram_sdf.v
# under CVC with selftest.sdf.  Prints SELFTEST PASS/FAIL; exit 0 on PASS.  ~10 s.
#   src_int8/flow/sdf_gls/checks/model_selftest/run.sh [build dir]   (default src_int8/flow/build/sdf_gls/selftest)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
GLS=$(dirname "$(dirname "$HERE")")
FLOW=$(dirname "$GLS")
ROOT=$(dirname "$(dirname "$FLOW")")
B=${1:-$FLOW/build/sdf_gls/selftest}
mkdir -p "$B"
CVC=$("$GLS/tools/setup_cvc.sh") || exit 2
python3 "$GLS/models/gen_cells.py" "$PDK_ROOT/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3/lib/gf180mcu_as_sc_mcu7t3v3__tt_025C_3v30.lib" \
    "$ROOT/3V3lib/gf180mcu_as_sc_mcu7t3v3-main/pdk/libs.ref/gf180mcu_as_sc_mcu7t3v3/verilog/gf180mcu_as_sc_mcu7t3v3.v" \
    "$B/cells.v" >/dev/null || exit 1
cp "$HERE/selftest.sdf" "$B/"
cd "$B"
flock "$FLOW/build/sdf_gls/.cvc_compile.lock" "$CVC" +typdelays -o "$B/selftest" "$HERE/tb_selftest.v" \
    -v "$B/cells.v" -v "$GLS/models/sram_sdf.v" > compile.log 2>&1 || { echo "SELFTEST FAIL: compile"; exit 1; }
./selftest > run.log 2>&1
n566=$(grep -c '\[566\] timing violation' run.log)
nexp=$(grep -A1 '\[566\] timing violation in tb_selftest.f1 ' run.log | grep -c 'setup(of setuphold)((posedge D)')
n667=$(grep -c '\[667\]' run.log)
grep -E '^(FAIL|SELFTEST)' run.log
if grep -q '^SELFTEST DONE (0 errors)' run.log && [ "$n566" = 1 ] && [ "$nexp" = 1 ] && [ "$n667" = 2 ]; then
    echo "SELFTEST PASS: CLK->Q through MIPD, SRAM read through bit MIPDs, edge-specific setup, negative hold"
    exit 0
fi
echo "SELFTEST FAIL: $n566 violations ($nexp expected setup posedge-D), $n667 negative-limit clamps (log $B/run.log)"
exit 1
