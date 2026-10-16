# Approximate INT8 multiplier, phase B: literature shortlist and the reproduced C-SSM

Goal: pick a recent (2020+, peer-reviewed IEEE) approximate multiplier that is efficient and
applicable to signed INT8, check how much it would cost the byte-LM, and reproduce it as an
`mq_mul8` variant (`docs/mul8_swap.md`). The full RTL benchmark (`docs/bench.md`) is phase C.

## 1. What the LM tolerates (emulator probes)

Emulator screen (`bench/emu`, 512 crops x 1,024 bytes, BPB change against the exact golden on
the same crops, paired SE about 0.001). The exact baseline is 1.3843 BPB.

| Probe (behavioural) | Error | dBPB |
|---|---|---:|
| exact + 2 (constant bias) | E = +2 on every product | +0.058 |
| two's-complement truncation of 4 LSBs (`example_trunc4`, 88 crops) | -7.5 mean, floor | +0.441 |
| sign-magnitude truncation of 4 LSBs (towards zero) | 0 mean, MED 6.5 | +0.017 |
| clear LSB only (phase A) | MED 0.5 | +0.002 |

The products feed dot products of 64 to 128 terms, and the requantisation has no bias
correction. An error that does not depend on the product's sign therefore piles up in every
output, and a constant +2 costs as much as an unbiased error with MED 90. The operands seen by
`mq_mul8` (`approx/act/hist.py`, 4 crops x 128 tokens, 48,512 products per token) make this
worse:

- activations are small: mean |b| = 19, 79 % have |b| < 32 and 6.9 % are 0;
- weights are larger: mean |a| = 38, 51 % have |a| < 32.

Designs whose error is two-sided or sign-symmetric, and zero for small operands, are the ones
that can be "minimal error" here. Most approximate-compressor designs extended to two's
complement fail this.

## 2. Shortlist

Our metrics come from an exhaustive 8-bit model of each design (`approx/screen/models.py`),
with NMED = MED / 2^14 (signed MaxOut). The hardware columns are the papers' figures against
their own exact baselines.

| Design | Signed? | Published 8-bit error | Published hardware (savings vs exact) | Our model: MED / bias | Emulator dBPB (512 crops) |
|---|---|---|---|---|---:|
| **Du et al., "A Low-Power DNN Accelerator With Mean-Error-Minimized Approximate Signed Multiplier", IEEE OJCAS 5:57-68, 2024** (Baugh-Wooley, trunc_num=7, compensation 192, probability-optimised compressor) | yes (BW) | ER 0.99, ME 20.24, NMED 5.56e-3 | 28 nm: area -46.4 %, power -49.8 %, delay -24.6 % | 92.1 / -0.25 (model without the compressor; NMED 5.62e-3 matches) | **+8.67** (trunc_num=4: +0.058) |
| **Strollo et al., "Comparison and Extension of Approximate 4-2 Compressors for Low-Power Approximate Multipliers", IEEE TCAS-I 67(9):3021-3034, 2020**, signed C-N | yes (BW) | Yang1: ER 0.05, NMED 3.26e-4, MRED 3.13e-2. Proposed: ER 0.09, NMED 5.43e-4 | 28 nm, signed Prop-CN about -9 % power (read off Fig. 10 of the 2022 paper) | 9.0 / -9.0 (simplified Yang1 tree) | **+3.98** |
| **Ansari, Cockburn, Han, "An Improved Logarithmic Multiplier for Energy-Efficient Neural Computing", IEEE TC 70(4):614-625, 2021** (ILM) | sign-magnitude | not checked (paper not open access) | not checked | 113.7 / 0.00, MRED 2.82 % | **+0.066** |
| **Strollo et al., "Approximate Multipliers Using Static Segmentation: Error Analysis and Improvements", IEEE TCAS-I 69(6):2449-2462, 2022** (signed C-SSM) | **yes, native** | Table III, n=8: m=4 and m=6 (see Sec. 4) | 28 nm signed power (Fig. 10): C-SSM m=4 about -64 %, m=5 about -41 %, m=6 about -4 % | m=6: 91.2 / +0.52; m=7: 26.7 / 0.00 | m=4 +3.80, m=5 +0.78, **m=6 +0.072**, m=7 +0.010 |
| Mitchell (1962), reference point only | sign-magnitude | | | 151.3 / 0.00 | +0.168 |

Two designs were not shortlisted because they are not drop-in replacements for `mq_mul8`:

- Spantidi et al., "Positive/Negative Approximate Multipliers for DNN Accelerators", ICCAD 2021,
  is unsigned [0, 255] and needs a mode chosen per weight.
- Zervakis et al., "Control Variate Approximation for DNN Accelerators", DAC 2021, adds a
  correction term to the accumulator.

### Choice: signed C-SSM (Strollo et al., TCAS-I 2022)

- **Reproducible.** The paper is open access and gives closed-form equations (15)-(20) for the
  signed segmentation and correction, plus exact 8-bit error tables. Our exhaustive metrics
  match all four n=8 rows to every printed digit (Sec. 4).
- **Signed and LM-friendly.** C-SSM is natively two's complement and needs no sign-magnitude
  conversion.
  - It is exact whenever both operands fit in m signed bits, which covers most activations
    here (79 % have |b| < 32, so m = 6 handles them exactly).
  - Its error is two-sided, with mean about 0.
  - Of the designs that save hardware, it is the only one whose LM cost stays in the +0.01 to
    +0.07 range. Du 2024 and the C-N compressor multipliers are biased and fail by +4 to +9 BPB.
- **Efficient.** The paper puts m = 4 and m = 5 on the power/accuracy Pareto front with 41-64 %
  power saving.
- **Caveat.** The configurations that keep the LM loss small (m = 6: +0.072, m = 7: +0.010)
  are the low-saving end of the family: the paper reports about 4-8 % power for m = 6, and our
  open-source area proxy gives -20 % area for m = 6 and +8.5 % for m = 7. The highly efficient
  m = 4 and m = 5 configurations break this LM (+3.8 and +0.78).

The variant is parametric: the default m = 6 is the paper's accurate 8-bit configuration.
Phase C should measure m = 6 and m = 7.

## 3. The reproduced design: `bench/variants/cssm.v`

`mq_mul8` is built from two `cssm_seg` operand blocks and one signed m x m inner multiplier.

- **Segment detection.** The alpha bits `X[7:m-1]` are all 0 or all 1 when X fits in m signed bits.
- **L/H mux.** Select `X[m-1:0]` (when X fits) or `X[7:8-m]`.
- **Correction, eq. (20).** The LSB of H becomes `X[8-m] | X[7-m]`.
- **Output shifter.** Shift the inner product left by 0, 8-m or 2(8-m).

The configuration is set with `` `define `` (tool command line): `CSSM_M` is the segment
width, default 6, and `CSSM_CORR` turns the correction on (1, default) or off (0, plain SSM).
`approx/ref/cssm.py` is the Python reference of the same equations.

## 4. Error reproduction (exhaustive, 65,536 inputs) vs the paper (Table III, n = 8)

The paper simulated 10 M random inputs. NM is mean(exact - approx) / 2^14, the paper's sign;
the other metrics use the same normalisation. Each pair below is ours / paper.

| m | Correction | NM | NMED | NoEB | MRED | NmaxED | PRED |
|---|---|---|---|---|---|---|---|
| 4 | no | -3.447e-3 / -3.45e-3 | 4.048e-2 / 4.05e-2 | 6.20 / 6.20 | 2.580e-1 / 2.58e-1 | 2.206e-1 / 2.21e-1 | 9.276e-1 / 9.28e-1 |
| 4 | yes | -7.458e-4 / -7.46e-4 | 3.061e-2 / 3.06e-2 | 6.55 / 6.55 | 1.811e-1 / 1.81e-1 | 2.188e-1 / 2.19e-1 | 9.056e-1 / 9.06e-1 |
| 6 | no | -1.459e-4 / -1.46e-4 | 6.656e-3 / 6.66e-3 | 8.59 / 8.59 | 2.637e-2 / 2.64e-2 | 4.633e-2 / 4.63e-2 | 5.246e-1 / 5.25e-1 |
| 6 | yes | -3.147e-5 / -3.15e-5 | 5.564e-3 / 5.56e-3 | 8.83 / 8.83 | 2.203e-2 / 2.20e-2 | 4.596e-2 / 4.60e-2 | 4.408e-1 / 4.41e-1 |
| 7 | yes (not in the paper) | 0 | 1.628e-3 | 10.27 | 4.832e-3 | 1.544e-2 | 2.104e-2 |

For the default m = 6 with correction:

- ER = 0.804, MED = 91.16, max |E| = 753, mean error (bias) = +0.516.
- The error is 0 whenever an operand is 0.
- Weighted by the chip's real operands (`--hist`): ER 0.444, MED 17.7, MRED 1.63 %, bias +0.22.

Functional checks:

- The RTL table (iverilog, exhaustive) equals `ref/cssm.py` on all 65,536 inputs for
  m = 4, 6, 7, with and without correction.
- The emulator uses that same RTL table.
- Sanity run `run_bench.sh cssm --n 8` (Verilator, full chip, 8 crops x 1,024 bytes, not the
  phase-C benchmark):
  - the emulator's logits equal the RTL's on all 8,192 tokens;
  - 450,412 clk per token (unchanged), no TB errors;
  - RTL - exact golden = +0.074 +- 0.006 BPB, consistent with the 512-crop screen (+0.072).

## 5. Hardware

### TSMC 65 nm (DC + PrimePower)

This is **pending**: the server became unreachable during this phase. The scripts are ready
(Sec. 6):

- same library and corners as the chip (tt for power, ss for timing);
- the chip's input driver and 4x output load, wire-load model, `compile_ultra`;
- a `set_max_delay` sweep for the area-delay curve;
- exact baselines: DC `a*b` (`exact`) and a structural Baugh-Wooley + Dadda multiplier
  (`bench/variants/exact_dadda.v`, generated, 35 FA + 7 HA, the paper's baseline type);
- power from an SDF-annotated VCS simulation, so glitches are included, with a SAIF window of
  65,536 operations into PrimePower;
- two vector sets: uniform random, and the real `mq_mul8` input stream of the chip TB.

### Open-source proxy (not 65 nm)

yosys `synth -booth` + abc, gf180mcu 7-track tt, OpenSTA, `syn/oss_proxy.sh`. Area only, no
power.

| Design | Area um2 | vs `a*b` | Delay ns |
|---|---:|---:|---:|
| exact `a*b` (yosys Booth) | 5,391 | | 5.45 |
| exact_dadda (structural) | 5,861 | +8.7 % | 3.92 |
| C-SSM m=4 | 2,452 | -54.5 % | 3.86 |
| C-SSM m=5 | 3,442 | -36.2 % | 4.48 |
| C-SSM m=6 | 4,327 | -19.7 % | 4.66 |
| C-SSM m=7 | 5,850 | +8.5 % | 5.40 |

The area trend in m matches the paper's power trend. At m = 7 the input muxes and output
shifter cost more than the smaller inner multiplier saves.

## 6. Commands (any variant name; `exact`, `exact_dadda` and `cssm` exist)

```
python3 -m src_int8.approx.err.run cssm -D CSSM_M=6 --ref cssm --hist build/approx/act/hist.npy
python3 -m src_int8.approx.screen.rom <model>            # behavioural candidates -> ROM variant
python3 -m src_int8.bench.emu.run cssm build/bench/c512x1024 [--n 128]
python3 -m src_int8.approx.act.hist                      # operand histogram (chip-weighted metrics)
src_int8/approx/act/dump_stream.sh && python3 -m src_int8.approx.act.vectors   # power vectors
python3 -m src_int8.approx.rtl.gen_dadda                  # structural exact baseline
src_int8/approx/syn/oss_proxy.sh <variant> "5000" [CSSM_M=6]                   # local proxy
# server (65 nm; vectors up with syn/sync.sh vec, summaries down with syn/sync.sh pull):
src_int8/approx/syn/run_dc.csh <variant> tt <max_delay_ns> [CSSM_M=6]
src_int8/approx/syn/sweep_dc.sh <variant> tt "0.6 0.8 1.0 1.5 2.0 3.0" [CSSM_M=6]
src_int8/approx/syn/run_power.csh <syn_tag> random|chip [period_ns=10]
```
