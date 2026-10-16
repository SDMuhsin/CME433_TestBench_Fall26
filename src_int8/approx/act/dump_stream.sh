#!/usr/bin/env bash
# Record the input stream of mq_mul8 in the 31-token chip TB (iverilog, golden vectors):
#   src_int8/approx/act/dump_stream.sh [n_changes=200000]  -> build/approx/act/mul8_stream.hex
# One "aabb" hex line per input change of the multiplier (all lane steps, not only w8 MACs:
# mq_dp feeds a[7:0], b[7:0] of the lane operands to mq_mul8 every cycle). Needs the chip
# vectors of src_int8/tb/run_chip.sh (src_int8/tb/build/vec/chip).
set -eu
SRC=$(cd "$(dirname "$0")/../.." && pwd); ROOT=$(dirname "$SRC")
OUT=$ROOT/build/approx/act; mkdir -p "$OUT"
VEC=$SRC/tb/build/vec/chip
[ -f "$VEC/plan.memh" ] || { echo "FAIL: no $VEC (run src_int8/tb/run_chip.sh first)"; exit 1; }
RTL=$(sed -e '/^\/\//d' -e '/^int\/mq_mul8\.v$/d' -e "s|^|$SRC/rtl/|" "$SRC/rtl/chip.f")
iverilog -g2012 -I "$SRC/rtl/nonlin" -I "$SRC/rtl/seq" -I "$SRC/tb/common" -s tb_mq_chip \
    -o "$OUT/tb_dump.vvp" $RTL "$SRC/approx/act/mq_mul8_dump.v" "$SRC/rtl/mem/gf180_sram_macro.v" \
    "$SRC/tb/chip/tb_mq_chip.sv" 2>"$OUT/tb_dump.compile.log"
cd "$ROOT"
vvp -n "$OUT/tb_dump.vvp" "+VEC=$VEC" "+MUL8_DUMP=$OUT/mul8_stream.hex" "+MUL8_MAX=${1:-200000}" >"$OUT/tb_dump.log"
echo "$(wc -l < "$OUT/mul8_stream.hex") input changes -> $OUT/mul8_stream.hex"
