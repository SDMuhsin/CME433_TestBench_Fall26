# Shi et al. 2025: hybrid approximate multipliers (HAM)

W. Shi, X. Cao, Z. Zou, Y. Gao, J. Wu, "Hybrid Approximate Multipliers With Merits Balance for
Digital Processing and Neural Networks", IEEE Trans. VLSI Systems 33(10):2795-2805, 2025,
doi:10.1109/TVLSI.2025.3587279.

## 1. What the paper proposes

A logarithmic multiplier writes |A| = 2^k (1 + f) and Mitchell's approximation drops the
f1 f2 term of the mantissa product p1 = (1 + f1)(1 + f2). The HAM keeps the logarithmic
front and back end but fits p1 with a piecewise-linear (PWL) surface (Fig. 1, eqs. 3-6):

- **Variables.** X1 = f1 + f2, X2 = the difference of the 4 upper mantissa bits, X3 = the sum
  of the 3 upper mantissa bits, X4 = min(f1, f2) (selected by the sign of X2).
- **Five zones** (Fig. 1(c)): Zone 1 X3 < 1/2, Zone 5 X3 >= 5/4; in between Zone 2/3/4 by
  |X2| <= 3/16, 4/16..8/16, >= 9/16.
- **Fit (eq. 6)**, slopes of one or two powers of two, five biases (Table I):
  Zone 1 X1 + X4/4 + Bias1, Zones 2-3 X1 + X1/2 + Bias2/3, Zone 4 X1 + X4 + Bias4,
  Zone 5 2 X1 - X1/16 + Bias5. Three shifted terms, one 3:2 compressor and one adder.
- **Two types** (Section II-B): HnC1 keeps the n upper bits of p1_PWL and X1, with the carry
  from the bit below (C1); HnLm adds the n upper bits exactly and OR-s the m lower ones (LOA).
- **Sign handling** (Fig. 3, 4): magnitudes by partial complement (PACC: invert, +1 on the 4
  LSBs only, no carry into the upper bits) or one's complement (OC); the result by sign
  compensation (SC, HnC1: biases pre-reduced by one LSB, the vacant carry bit of the 3:2
  compressor = ~sign, then invert, which is an exact negation) or OC (HnLm).
- **Shift**: p1_PWL shifted by K = e1 + e2; HnC1 rounds right shifts with bring-in carry
  truncation (BCT, Fig. 5(a)); the SO / SP versions keep only 16 of the 31 output bits (Fig. 5(b)).

The 16-bit designs are H9C1 (accuracy) and H6L9 (speed), each with -SP / -SO versions (Tables
I-IV, 45 nm Nangate, 500 MHz). For 8 bits the paper gives three H7C0 designs, HAM-A/B/C, with
X2 kept to 3/2/2 and X4 to 5/4/3 upper bits (Table V), and reports them as the 8-bit designs
with the best NMED and MRED (HAM-A 2.7e-3 / 1.29 %). They are used in LeNet-5 / VGG16 /
ResNet18 and MoveNet (Table VII) with near-exact accuracy.

## 2. Reproduction (`src_gan_tsmc65/approx/`)

- `ham.py`: bit-exact integer model, one dataclass `Ham` for every type (`n`, `m`, `c`,
  biases, X2 / X3 / X4 widths, zone thresholds, ME `pacc|oc|exact`, MTS `sc|oc`, BCT, output
  `full|sp|so`), with the `products()` interface of `mult.Multiplier`, so `check.py` and
  `exhaustive.py` take it unchanged. `PAPER16` holds the six 16-bit designs of Tables I-II,
  `HAM8` the 8-bit HAM-A/B/C.
- The paper's Algorithm 1 example (H6L9, A = 16'h050a, B = 16'hfef2) gives every intermediate
  value as printed and the output 31'h7ffac1e0.
- Reading of the paper used by the model: e = k + 1 (Algorithm 1); P1 carries q = n - 2
  (HnC) or n + m - 2 (HnLm) fraction bits, the product is P1 * 2^(K - 2 - q); HnC1 uses an
  (n - 1)-bit mantissa and floors the exact sum to n bits (the carry from the one dropped
  column is the C1 carry), HnC0 an (n - 2)-bit mantissa; HnLm adds t1 + t2 + bias above bit m
  without carry-out and ORs the three terms below (Algorithm 1 lines 21-22), Zone 5 subtracts
  X1/16 in two's complement. SC is modelled as its result, -P1 for a negative product.
- A zero magnitude gives 0 (Algorithm 1 line 28 tests A == 0 || B == 0; the model also catches
  a PACC magnitude of 0, which the 8-bit PACC produces for -16).
- `ham_v.py`: Verilog of the signed 8 x 8 `gan_mul8` (behavioural, like the paper's
  DC-synthesised design): ME, exponent / mantissa conversion (LOD + normalising shift), the
  PWL module (X1..X4, zone decode, three-term adder with the zone bias minus 1 and the carry
  ~sign), one's-complement MTS, arithmetic shift by k1 + k2, zero flag.
  `python3 -m src_gan_tsmc65.approx.gen` writes `bench/variants/ham_*.v`.
- `paper_shi2025.py` -> `approx/results/shi2025_error.md` (40 s on 24 cores): Algorithm 1,
  Table III on the paper's 16-bit grid (a, b = -2^15 .. 2^15 - 1, step 8: 8192^2 pairs; MRED
  averages |E| / max(1, |exact|) over all pairs, NMED = MED / 2^30), Table V 8-bit unsigned
  exhaustive (NMED = MED / 255^2), and `fit()` for the 8-bit biases. `exhaustive.signed_stats`
  gained a `step` option, `metrics.ErrorStats` a `PRED5` (RED < 5 %).

## 3. Error metrics vs the paper (`approx/results/shi2025_error.md`)

| Paper table | Design | MRED (%) ours / paper | NMED (1e-3) ours / paper | RED < 2 % ours / paper |
|---|---|---|---|---|
| III, 16 bit | H9C1 (PACC, SC, BCT) | 0.786 / 0.68 (+15.6 %) | 1.632 / 1.642 (-0.6 %) | 95.13 / 96.21 % |
| III, 16 bit | H9C1-SP (OC, SC) | 0.721 / 0.72 (+0.2 %) | 1.627 / 1.642 (-0.9 %) | 95.74 / 95.59 % |
| III, 16 bit | H9C1-SO (OC, SC) | 0.735 / 0.72 (+2.0 %) | 1.627 / 1.642 (-0.9 %) | 95.74 / 95.87 % |
| III, 16 bit | H6L9 (PACC, OC) | 2.215 / 1.30 (+70 %) | 5.198 / 3.109 (+67 %) | 53.85 / 78.95 % |
| III, 16 bit | H6L9-SP / -SO (OC, OC) | 2.190 / 2.203 vs 1.38 / 1.41 | 5.173 vs 3.113 | 53.7 vs 77.9 % |
| V, 8 bit | HAM-A (X2 3, X4 5 bits) | 1.085 / 1.29 (-15.9 %) | 2.725 / 2.7 (+0.9 %) | - |
| V, 8 bit | HAM-B (X2 2, X4 4 bits) | 1.265 / 1.42 (-10.9 %) | 2.985 / 3.0 (-0.5 %) | - |
| V, 8 bit | HAM-C (X2 2, X4 3 bits) | 1.331 / 1.57 (-15.2 %) | 3.119 / 3.3 (-5.5 %) | - |

- **H9C1 family: reproduced.** The -SP / -SO versions match all four metrics within 2 %
  (RED < 5 %: 99.75 / 99.74 vs 99.77 / 99.85 %). H9C1 itself matches NMED but its MRED is
  16 % high, entirely from PACC: on the step-8 grid half of the negative operands end in 0000,
  PACC drops their carry and |A| comes out 16 too small (relative error 16 / |A|). With OC
  magnitudes the same core gives 0.681 % / 1.626e-3 / 96.19 % / 99.95 %, i.e. Table III's H9C1
  row; the paper's H9C1 numbers evidently come from a model without the PACC carry loss. BCT
  changes MRED by < 0.001 % on this grid.
- **H6L9: not reproduced** (+70 % MRED, +67 % NMED). The model follows Algorithm 1 bit for bit
  (its worked example is exact), but the two OR stages (X1 low bits, then p1_PWL low bits) lose
  the carries of 9 bits twice, -2.4 % of p1 on average, which the Table I biases (within 3/256
  of H9C1's) do not compensate. Applying the LOA in only one of the two places gives 1.19 % /
  1.17 % MRED and 2.71 / 2.54e-3 NMED, bracketing the paper's 1.30 % / 3.109e-3; the paper's
  H6L9 metrics therefore come from a different LOA placement than Algorithm 1 shows, which the
  text does not specify.
- **8-bit HAM-A/B/C**: the paper prints neither the 8-bit biases nor the zone thresholds for
  the shorter X2. We map Fig. 1(c) to the coarser X2 (|X2| <= 3/16 -> |X2| <= 1/8 for 3 bits and
  0 for 2 bits; >= 9/16 -> >= 5/8 and >= 3/4) and fit the five biases (units 2^-5) by
  coordinate descent on the unsigned exhaustive MRED (`fit`), as the paper describes its
  "iterative simulation". With the paper's evaluation set evidently unsigned (0..255; the
  signed set with PACC gives 3 % MRED), NMED matches within 1-6 % and the A < B < C order of
  both metrics holds; our MRED is 11-16 % lower, plausibly because our biases are tuned for
  MRED (an NMED-tuned fit moves MRED by < 0.04 %).
- **Hardware trends (Table V, 45 nm)**: HAM-A/B/C are 1.7-2.2x the area and 1.7-2.3x the power of
  DR-ALM-4/5 and 0.1-0.2 ns slower, i.e. the PWL fit costs more than the DR-ALM's truncation;
  the paper prints no exact 8-bit multiplier. Our chip results in section 5 follow the same
  order against our dralm_* variants.

## 4. Student variants (signed 8 x 8, `gan_mul8`)

The paper's 8-bit design is H7C0 (7 upper p1_PWL bits = 2 integer + 5 fraction bits, 5-bit
mantissas, no carry from the bits below). Signed handling follows the paper's HnC scheme: PACC
magnitudes (7 bits, as the 16-bit design's 15) and SC at the output, which is an exact negation
at the cost of one inverter row and a carry-in. Variants: the paper's most accurate (HAM-A) and
its cheapest-fit (HAM-C) design, plus one ablation of the input sign unit. All three share the
fitted HAM-A / HAM-C cores of section 3.

| Variant | Design | RTL == Python | MAE / bias, all | MAE / bias, b >= 0 | max abs error | error rate | MRED | NMED |
|---|---|---|---|---|---|---|---|---|
| `ham_a` | HAM-A, PACC + SC (paper) | 65536/65536 | 99.77 / -0.25 | 69.35 / +31.75 | 3840 | 94.48 % | 3.09 % | 6.09e-03 |
| `ham_c` | HAM-C, PACC + SC (paper) | 65536/65536 | 106.86 / -0.25 | 77.50 / +31.75 | 3840 | 96.29 % | 3.37 % | 6.52e-03 |
| `ham_ae` | HAM-A, exact magnitudes + SC (ablation) | 65536/65536 | 39.95 / +0.01 | 39.59 / -0.25 | 512 | 92.99 % | 1.07 % | 2.44e-03 |

(`python3 -m src_gan_tsmc65.approx.check ham_a ham_c ham_ae`, MRED over non-zero products;
zero products exact, `zero_hits` = 0.) At 8 bits PACC is lossy: every negative operand that
ends in 0000 loses 16, so -16 becomes 0, -32 becomes 16 and -128 becomes 112 (2 % of this
chip's weights are negative multiples of 16). That alone is the +31.75 bias at b >= 0 and
triples the MRED; with exact magnitudes (`ham_ae`) the signed error is the core's own (MRED
1.07 %, unbiased). The paper's own number, MRED 1.29 % for HAM-A, is only consistent with
unsigned or exact-magnitude operands.

## 5. Results in the chip

Full rows in `docs/results.md` s.5 (DC ss 2.4 ns, PT and PrimePower tt SDF at 2.5 ns = 400 MHz;
FID from 10,000 RTL images; delays from the 1.8 ns netlists at 2.0 ns). Percentages vs `exact`.

| Variant | PSNR (dB) / labels | FID-10k | 16 x mul8 area | mul8 power (SDF) | Chip power | Energy/image | Min period | mul8 delay |
|---|---|---|---|---|---|---|---|---|
| exact (`a * b`) | inf / 100 % | 78.65 | 9,890 um^2 | 0.192 mW | 8.816 mW | 51.72 uJ | 1.817 ns | 0.937 ns |
| dralm_t5 (Yin 2021) | 23.45 / 90.2 % | 77.12 | 6,396 (-35.3 %) | 0.142 (-25.7 %) | 8.805 (-0.1 %) | 51.66 (-0.1 %) | 1.817 (+0.0 %) | 1.001 (+6.8 %) |
| ham_a | 21.68 / 84.8 % | 84.67 | 38,717 (+291.5 %) | 1.281 (+568.7 %) | 10.184 (+15.5 %) | 59.75 (+15.5 %) | 2.470 (+35.9 %) | 1.678 (+79.1 %) |
| ham_c | 21.59 / 84.8 % | 84.79 | 36,639 (+270.5 %) | 1.197 (+524.8 %) | 10.115 (+14.7 %) | 59.34 (+14.7 %) | 2.481 (+36.5 %) | 1.690 (+80.4 %) |
| ham_ae | 38.24 / 97.3 % | 78.90 | 42,339 (+328.1 %) | 1.227 (+540.7 %) | 10.122 (+14.8 %) | 59.38 (+14.8 %) | 2.475 (+36.2 %) | 1.682 (+79.5 %) |

- **Criterion (at least one better hardware metric): met by none of the three.** Every column is
  worse than exact, by about as much as `mq:ilm` (+334 % mul8 area, +16 % energy).
- **Why: the datapath, not the sign units.** PACC is a 4-bit incrementer per operand and SC an
  inverter row with a carry-in; replacing PACC by exact negation (ham_ae) adds 3,622 um^2 (+9 %).
  The HAM chains LOD, normalising shift, the PWL fit (X1 / X2 / X3 adders, zone decode, X4
  select, three-term adder), the MTS inverters and a 16-bit output shifter, all in the same cycle
  as the RF read and the PE accumulation. Its mul8 delay is 1.68 ns at the 1.8 ns target (exact
  0.94, dralm_t5 1.00), so the chip misses 500 MHz by 0.47 ns and at 400 MHz DC upsizes the
  whole path. At a relaxed 4.0 ns the 16 multipliers are 13,409 (ham_a) / 12,690 um^2 (ham_c)
  vs exact's 7,984 (+68 / +59 %, `results/syn_{exact,ham_a,ham_c}_ss_p4.txt`): even without
  timing pressure the PWL stage costs more than the array it replaces, and the 400 MHz netlist is
  2.9x that again. A generic 2-input mapping (yosys + abc) gives 359 gates for HAM-A vs 419 for
  exact but a logic depth of 42 vs 29, which is where the cost comes from.
- **Consistent with the paper's own 8-bit data.** Table V puts HAM-A/B/C at 1.7-2.2x the area and
  power of DR-ALM-4/5 and 0.1-0.2 ns slower; DR-ALMs save 25-42 % on exact in this chip, so a
  HAM lands above exact before any timing effect. The paper's headline savings (H9C1 -49 % area,
  -56 % power vs an exact radix-4 multiplier) are 16-bit results: the exact array grows with
  n^2, the HAM's LOD / PWL / shifter roughly with n.
- **Quality.** With the paper's PACC the chip loses 16 on every negative weight ending in 0000
  (2 % of the weights; -16 becomes 0), a +31.75 bias per product at b >= 0, FID 84.7 / 84.8
  (21.7 / 21.6 dB, 84.8 % labels). The HAM core itself is excellent: with exact magnitudes
  (ham_ae) FID 78.90 (exact 78.65), 38.2 dB and 97.3 % labels, the most faithful approximate
  multiplier in this testbench. HAM-A and HAM-C differ by 0.1 FID: the X2 / X4 truncation of
  HAM-C is invisible next to the PACC error.
- FM SUCCEEDED (2.4 and 1.8 ns netlists) for all three; PT ss setup at 2.5 ns +0.058 / +0.048 /
  +0.056 ns; ff hold passes for ham_a / ham_ae and misses by 0.7 ps on one endpoint for ham_c
  (`u_seq/u_rq/q_reg_3_` -> `u_seq/rq_res_reg_3_`, the known residue outside the multiplier,
  s.2 of results.md); GLS of seed_0 (zero delay and SDF) matches each variant's emulation
  784/784; 10,000/10,000 RTL images match the Python emulation for all three. Zero-delay power:
  chip 9.669 / 9.614 / 9.694 mW, mul8 0.959 / 0.890 / 0.981 mW (exact 8.741 / 0.187).

## 6. Notes

- The paper's printed 8-bit HAM metrics correspond to unsigned (or exact-magnitude) operands;
  its signed scheme at 8 bits (PACC) triples the MRED. A student who wants the HAM's accuracy
  should use exact magnitudes; one who wants its savings should not use it at 8 bits.
- `python3 -m src_gan_tsmc65.approx.paper_shi2025` takes about 40 s on 24 cores (six 16-bit
  designs and four ablations on 67 M pairs each); `--fit` re-derives the 8-bit biases.
