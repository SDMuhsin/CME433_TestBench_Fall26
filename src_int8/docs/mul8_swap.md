# The INT8 multiplier swap point (`mq_mul8`)

`mq_chip` has one physical multiplier for everything, the signed 24 x 17 `mq_mul24x17` in
`rtl/lane/mq_dp.v` (lane MACs 24 x 16 and the writeback's acc x M halves, `rtl_units.md`).
For approximate-multiplier studies the INT8 x INT8 products are taken out of it and sent
through one small module in one file:

| | |
|---|---|
| File | `src_int8/rtl/int/mq_mul8.v` (the exact reference; the default) |
| Module / ports | `mq_mul8 (input signed [7:0] a, input signed [7:0] b, output signed [15:0] p)` |
| Semantics | two's-complement signed 8 x 8 -> 16-bit product; exact: `p = a * b` |
| Timing | purely combinational, no clock, no reset; its output is registered by the lane's S1 stage (`mq_lane`, 40 ns cycle at 25 MHz, shared with the operand mux and the sign extension) |
| Operand ranges seen | `a` = streamed INT8 weight, [-127, 127] (the exporter never emits -128); `b` = INT8 activation, [-128, 127] |
| Used by | `mq_dp` (`u_mul8`), sign-extended to the lane's 40-bit product when `w8` is set |
| Filelists | `rtl/chip.f`, `rtl/units.f`, `flow/config.yaml`, `src_int8_tsmc65/rtl_mem/chip65.f` (the 65 nm port compiles the same `src_int8/rtl`) |

## Which multiplies go through it

The sequencer (`rtl/seq/mq_seq.v`) sets `lane_w8` for a MAC uop whose stream operand is one
byte (`sw == 1` and side a or b is `S`). In the microcode (`ucode/program.py`) these are exactly
the weight x activation products. Per token (ISA simulator count, trained parameters):

| Lane step class | per token | Multiplier |
|---|---:|---|
| INT8 weight (stream) x INT8 activation: `W_in_x`, `W_in_z` (2 x 96 x 64 each), conv taps w0 x CONV / w1 x xi (2 x 2 x 96), `W_x` (2 x 12 x 96), `W_dt` (2 x 4 x 96), `W_out` (2 x 64 x 96), `E_out` (128 x 64) | **48,512** | **`mq_mul8`** |
| LUT interpolation T[i] x (2^11 - f), T[i+1] x f (16 x 12 b) | 2,694 | `mq_mul24x17` |
| memory x register: H x dA, H x C (INT24 state), B[n] x u (8 x 8), x x r (RMSNorm scale) | 2,496 | `mq_mul24x17` |
| register x register: dt x bu, D x u (8 x 8), xc x sig, z x sig, y x sz | 1,536 | `mq_mul24x17` |
| x x x (RMSNorm mean square, 16 x 16) | 192 | `mq_mul24x17` |
| dt x A' (16 x 16, A' streamed as 16 b) | 768 | `mq_mul24x17` |
| writeback `acc x M` requantisation (32 x 16, two halves) | one per stored value | `mq_mul24x17` |

So 48,512 of the 56,198 lane steps per token (86 %) use `mq_mul8`. Two other products have
INT8 x INT8 operands but are not routed through it: `B[n] x U[d]` (768 per token, the exact
`bu` of the scan) and `D[d] x U[d]` (192). Both are activation x activation products in the SSM
recurrence, whose operands come from 16-bit registers, so the hardware cannot tell them from
16-bit products without a microcode change; they are 1.7 % of the INT8 products and stay exact.
"The INT8 multiplier" in this project therefore means the weight x activation multiplier of the
GEMV / conv / logit layers, which is also what approximate-multiplier papers apply to NN layers.

## Bit-exactness and cost of the refactor (exact `mq_mul8`)

- Cycle-identical: the 31-token chip TB (`tb/run_chip.sh`, iverilog and `--vl`) PASSes, 128/128 logits per
  token bit-exact, 450,412 clk START -> done (unchanged); unit TBs (rsh, sat, lane, wb, nlu)
  PASS; demo stories PASS; microcode tests PASS; and the benchmark (`docs/bench.md`) reproduces
  the golden logits bit for bit on 1,048,576 tokens.
- A simulation-only check in `mq_dp` prints `ERROR mq_dp: w8 MAC operand outside INT8` if a `w8`
  MAC ever had an operand outside 8 bits (none occurred).
- Area (yosys `synth_units.sh`, gf180mcu tt, pre-layout): `mq_mul8` 215 cells / 5,363 um2;
  `mq_dp` 3,327 cells / 87,779 um2 (was 3,067 / 82,401 um2 before the split, `rtl_units.md`),
  i.e. the dedicated 8 x 8 multiplier and its 40-bit mux cost +5,378 um2. The signed-off
  layouts (`flow/runs/mq_final`, the 65 nm port) were built from the RTL before this split;
  they were not re-run.

## Plugging in a design

1. Write a Verilog file that defines `module mq_mul8` with exactly the ports above
   (any submodules may live in the same file, or put several files in a directory). It must be
   combinational and synthesisable; keep the 16-bit signed output (an approximate design may
   return any 16-bit value; there is no saturation downstream of it except the INT32 accumulator,
   which cannot overflow for |p| < 2^15 over the longest dot product of 96 terms).
2. Put it at `src_int8/bench/variants/<name>.v` (or `<name>/*.v`); `variants/example_trunc4.v`
   is a template.
3. Run `src_int8/bench/run_bench.sh <name>` (`docs/bench.md`). The build replaces only the
   `int/mq_mul8.v` entry of `chip.f`; everything else is the signed-off RTL.
4. For a chip built with the variant (synthesis / flow), replace `src_int8/rtl/int/mq_mul8.v`
   (or its filelist entry) by the variant file. `syn/synth_units.sh` reports `mq_mul8` alone.
