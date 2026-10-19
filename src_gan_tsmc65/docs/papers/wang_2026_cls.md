# Wang et al. 2026: CLS-driven classified truncation approximate Booth multiplier

Y. Wang, L. Yao, S. Xiang, L. Xu, H. Wu, J. Gao, Z. Chen, T. Chen, H. Liang and Y. Xu, "A
CLS-Based Driven Classified Truncation Approximate Booth Multiplier for High-Fidelity Image
Processing", IEEE TVLSI 34(9):2783-2792, 2026.

Paper C of the 16-bit round (standalone multiplier bench `syn/mulbench/`, N = 16 main, N = 8 for
the current chip; `park_2023_r4.md`, `zhu_2022_r256.md`, `booth16_round.md`). No chip flow.

## 1. What the paper proposes
- **Signed radix-4 Booth, 8 x 8** (4 rows, sign extension "E E ~E" / "~E 1") split into three
  regions (Fig. 12): product columns 0-3 **truncated**, columns 4-7 an **approximation band**,
  columns 8-15 exact (exact encoder CPE, exact 4:2 compressors, FA / CLA).
- **Encoders** (Sec. III-A): CAE1 (eq. 4, 6 K-map entries flipped, 3 up / 3 down: no a_j-1
  input, so the +2 digit uses a_j, -2 gives 1, the 110 form of -1 gives 0) and CAE2
  (eq. 5, pp = a_j xor b_2i+1, 8 entries flipped).
- **4:2 compressors without cin / cout** (Table II): A4T2C_1 (eq. 6) with an "error
  compensation module" (a 4-input AND, Fig. 12), A4T2C_2 (eq. 7, three gates).
- **CTM, classified truncation compensation** (Sec. IV-A): the truncated t = 4 product bits are
  replaced by a word C(S) chosen by the constrained level selection (CLS) search: three levels
  from V = {2, 6, 10, 14} (low two bits fixed to "10") and thresholds on S = a[1:0] + b[1:0],
  minimising mean |e| (then a relative-error term) in the low-bit replacement model
  P' = floor(P / 16) 16 + C (eq. 23). Result {2, 6, 10}, eq. (18) / CTM1 (eq. 19).
  CTM2 (Fig. 11, used in the designs): a 2-bit feature Z = (a0, b0) chosen by explained variance
  (Table IV), C = {a0 b0, a0 xor b0, 1, 0} = 2 + 4 (a0 + b0) (one AND, one XOR).
- **Designs** (Sec. IV-B): ABMCT1 = CAE1 + A4T2C_1 + error compensation + CTM2, ABMCT2 = CAE2
  + A4T2C_1 + compensation + CTM2, ABMFT1 = CAE2 + A4T2C_2 + "0000" truncation.
  TSMC 90 nm, DC (Table VII): vs the exact multiplier area -25.6 / -34.9 / -37.9 %, power
  -20.9 / -29.6 / -32.9 %, delay -75 % (2.59 -> 0.64 ns); NMED 1.49 / 2.05 / 2.86e-3, MRED
  2.45 / 3.49 / 3.77e-2.
- The authors published their Verilog (three Vivado projects `wyh1/2/3`, GitHub link in the
  paper). It was used as the reference for the netlist structure (not committed here).

## 2. Reproduction (`src_gan_tsmc65/approx/`)
| File | Role |
|---|---|
| `cls_cells.py` | CAE1, CAE2 (+ zero-safe CAE2), A4T2C_1, A4T2C_2 |
| `cls_ctm.py` | candidate levels V_t, CLS search (any t, n), CTM1 / CTM2 tables and netlist, explained variance (Table IV) |
| `cls.py` | `cls(n, t, w, enc, comp, ctm, and4, zero_fix)` -> `mult.Multiplier` (netlist = bit-exact Python model and RTL); `PAPER` = the three designs and the Table VI ablations |
| `paper_wang2026.py` | Tables II-VII, CLS re-derivation, bench-design metrics (N = 16 also exhaustive) -> `approx/results/wang2026_error.md` |
| `mulbench.py` | `WANG` registry: `cls_*` at N = 16 / 8, plus `tacbm_12` (Aizaz & Khare 2022 at 16 bits) |
| `variants.py`, `gen.py` | chip variants `cls_ct1z`, `cls_ct1z2` (`bench/variants/`) |

**Fidelity to the authors' RTL.** All three published designs were simulated exhaustively in
iverilog (65,536 pairs) and `cls(8, 4, 4, ...)` equals them bit for bit:
`wyh1` = CAE1 + A4T2C_1 + CTM2 **without** the AND4 compensation, `wyh2` = ABMFT1,
`wyh3` = CAE2 + A4T2C_1 with "0000" truncation (no CTM, no AND4; the paper's ABMCT2 has both).
Structure taken from that RTL: the band compressors take their inputs in row order, then the
neg bits (c2 at column 4), then the carry of the previous band column of the same stage (column
5 uses carry4 as x4, the only "ripple"); neg bits of rows in the truncated columns are dropped;
the CTM word is written straight into product bits 3..0 (no carry into column 4). The AND4
"error compensation module" is not in the RTL; we add it as drawn in Fig. 12 (AND of the four
inputs of the band's top-column A4T2C_1, one bit into column 8). Two Table VI rows support this
reading (below). The printed eq. (6) has lost an overbar; the RTL form
sum = x2 (x1 + ~(x3 xor x4)), carry = x3 + x4 reproduces Table II exactly.

**Width parameters / scaling.** t = truncated columns, w = band width, t + w <= n (the sign
bits stay exact). Band compressor stages repeat while a band column has >= 4 bits (at n = 8 one
stage, as in the RTL); one AND4 per A4T2C_1 of the top band column. The CLS search is re-run
for each t (as the paper does for Table III): V_t = {(2m + 1) 2^(t-3)}, i.e. the low t - 2 bits
fixed to "10..0" and the top two bits free (t = 4: {2, 6, 10, 14}); CTM2 = level indexed by
a0 + b0. At N = 16 the paper's split (t = w = n / 2) gives t = w = 8 and CLS levels
{32, 96, 160} (`cls_ct1`, `cls_ct2`, `cls_ft1`); `cls_ct1z6` narrows the band to w = 6
(accuracy comparable to `park_14z`). At N = 8 the bench uses the paper's own t = w = 4 and
`cls_ct1z2` a 2-column band.

## 3. Error metrics vs the paper (8-bit, exhaustive; `approx/results/wang2026_error.md`)
**Local tables reproduce exactly.** Table II: all 16 rows of both compressors (the paper's
"61/256" error rate of A4T2C_2 counts the -2 entry twice). K-map flips: CAE1 3 + 3, CAE2 8.
Table IV: EV 9.78 / 7.07 / 5.16 / 7.07 %, MSE 20.75 / 21.38 / 21.81 / 21.38 and
E[P_L | Z] exactly. Table V (low-bit replacement model): ME, MAE and NMED (NMED = MAE / 255^2)
of Const 0000 / 0010 / 0110, CTM1 and CTM2 all exact (e.g. CTM2 -0.5 / 4.06 / 6.248e-5);
PRED@10 % is 0.990 vs 0.9975 (definition unclear), Q99 10 vs 9 for CTM1 / 2.

**CLS search.** Levels {2, 6, 10} are reproduced, but the stated objective (min mean |e|) picks
thresholds T1 = 1, T2 = 3 (low-bit MAE 3.906) instead of the paper's 2, 4 (4.094, the printed
CTM1). Nothing in the paper's constraints excludes (1, 3); it does not matter for the designs,
which use CTM2 (levels only). The low-bit model ignores the carries and neg bits of the real
truncated region (E[P_L] = 12.25 vs 6.5 for the nibble), so the CLS levels under-compensate in
the multiplier (exact Booth + CTM2, t = 4: bias -6.25).

**Table III** (exact encoder / compressors, CTM1 re-derived per t):

| t | NMED ours / paper | MRED ours / paper |
|---|---|---|
| 2 | 0.069e-3 / 0.11e-3 | 0.20 % / 0.27 % |
| 3 | 0.26e-3 / 0.28e-3 | 0.68 % / 0.69 % |
| 4 | 0.43e-3 / 0.50e-3 | 1.19 % / 1.35 % |
| 5 | 1.45e-3 / 1.47e-3 | 3.47 % / 3.54 % |
| 6 | 2.83e-3 / 2.79e-3 | 7.00 % / 6.97 % |

**Tables VI / VII (the multipliers)** — NMED = MED / 2^14 (it matches the paper's Exact_CTM):

| design | NMED ours / paper | MRED ours / paper | bias ours / paper |
|---|---|---|---|
| Exact_CTM | 0.477e-3 / 0.47e-3 | 1.33 % / 0.13 % | -6.25 / -2.67 |
| CAE1_only | 7.60e-3 / 0.76e-3 | 20.4 % / 2.03 % | -6.25 / -2.73 |
| CAE2_only | 8.44e-3 / 1.15e-3 | 37.4 % / 4.35 % | +107.8 / +43.0 |
| A4T2C1_only (+ AND4) | 4.75e-3 / 0.47e-3 | 17.93 % / 1.79 % | -10.0 / -5.99 |
| A4T2C2_only | 5.32e-3 / 0.53e-3 | 10.93 % / 1.10 % | -53.8 / -29.8 |
| ABMCT1 (+ AND4) | 7.98e-3 / 1.49e-3 | 24.51 % / 2.45 % | -8.5 / - |
| ABMCT2 (+ AND4) | 9.30e-3 / 2.05e-3 | 40.4 % / 3.49 % | +93.8 / - |
| ABMFT1 (= authors' RTL) | 8.46e-3 / 2.86e-3 | 32.9 % / 3.77 % | +29.4 / - |

- **The MRED column of Tables VI / VII is ours / 10** for 6 of 8 rows to within 1 % (Exact_CTM
  1.33 vs 0.13, CAE1_only 20.38 vs 2.03, A4T2C1_only 17.93 vs 1.79, A4T2C2_only 10.93 vs 1.10,
  ABMCT1 24.51 vs 2.45), including Exact_CTM, which has no approximate cell and whose NMED
  matches unscaled; the ablation NMEDs are also ours / 10 to 1 %. The structures are therefore
  the paper's, and the printed MREDs (and ablation NMEDs) are low by a factor of 10. The real
  8-bit designs have **MRED 25-40 %**, not 2.5-3.8 %. The authors' own RTL (`wyh1` 24.27 %,
  `wyh2` 32.91 %, `wyh3` 35.95 %) confirms it.
- ABMCT1 / A4T2C1_only match the paper's MRED only with the AND4 into column 8 (without it
  24.27 / 18.01 %), which is how `PAPER` builds them. ABMCT2 is 16 % above (11.6x; without the
  AND4 36.6 %, 10.5x) and ABMFT1 13 % below (8.7x); Table VII NMED and the biases are not
  reproduced by any normalisation (the biases are 1.8-2.5x ours).
- Source of the error: the band holds the high-probability bits of the low half. CAE1 replaces
  every +2 digit by +1-like bits, A4T2C_1 loses 1 on the frequent "1000" input (row 0 alone),
  A4T2C_2 ORs four bits. Small products are hit hardest (MRED), while NMED stays moderate.
- Not reproduced: hardware of Tables III / VI, the comparison designs of Table VII, Fig. 8 / 14
  and the image experiments.

## 4. Bench designs, zero products and the fix
| Design | N | t, w | what |
|---|---|---|---|
| `cls_ct1`, `cls_ct2`, `cls_ft1` | 16 | 8, 8 | ABMCT1 / ABMCT2 / ABMFT1 at the paper's split scaled (t = w = n/2) |
| `cls_ct1z`, `cls_ft1z` | 16 | 8, 8 | + zero fix |
| `cls_ct1z6` | 16 | 8, 6 | ABMCT1, 6-column band, zero fix |
| `cls_ct1`, `cls_ct2`, `cls_ft1`, `cls_ct1z`, `cls_ft1z` | 8 | 4, 4 | the paper's designs (+ zero fix) |
| `cls_ct1z2` | 8 | 4, 2 | ABMCT1, 2-column band, zero fix (chip variant) |

**Zero products** (b = activation, recoded). ABMCT1 / 2: the CTM adds 2 + 4 a0 (16 bits:
32 + 64 a0) to every product, so **a x 0 != 0 for all a**; CAE2 / ABMFT1: the digit 000 gives
pp = a_j, so a x 0 = (a's band bits) != 0 for 255 / 256 a. **0 x b** is wrong for ~all b in every
design (CTM word; CAE1 gives 1 for the digit -2, CAE2 the one's complement without its +1).
**Minimal fix (`*z`)**: the CTM word AND OR(b) (one n-input OR, t AND gates); for CAE2 the
zero-safe encoder (a_j xor b_2i+1) AND OR(b_2i+1, b_2i, b_2i-1). Then b = 0 gives exactly 0
(0 / 65,536 and 0 / 256 wrong); 0 x b stays wrong. The fix does not change any other product
of ABMCT1 (identical MRED); for ABMFT1 it also zeroes the 000-digit rows (MRED 1.00 -> 0.68 %).

Error metrics (N = 16 exhaustive, 2^32 pairs; GAN-like = the bench's power stimulus, 200 k
pairs; N = 8 exhaustive):

| Design | ER | MAE | bias | max abs E | NMED (/2^(2N-2)) | MRED | GAN-like bias / MAE |
|---|---|---|---|---|---|---|---|
| `cls_ct1` (16) | 100.00 % | 53,619 | +8,870 | 407,164 | 4.99e-5 | 0.686 % | +3,258 / 19,190 |
| `cls_ct2` (16) | 100.00 % | 69,779 | +55,592 | 528,480 | 6.50e-5 | 1.529 % | +187,300 / 190,900 |
| `cls_ft1` (16) | 100.00 % | 53,904 | -7,287 | 347,222 | 5.02e-5 | 1.001 % | +118,100 / 136,600 |
| `cls_ct1z` (16) | 100.00 % | 53,619 | +8,870 | 407,164 | 4.99e-5 | 0.686 % | +3,217 / 19,150 |
| `cls_ft1z` (16) | 99.97 % | 55,173 | -30,602 | 347,222 | 5.14e-5 | 0.685 % | -12,140 / 19,190 |
| `cls_ct1z6` (16) | 99.99 % | 12,252 | +1,377 | 83,818 | 1.14e-5 | 0.161 % | +700 / 4,357 |
| `tacbm_12` (16) | 99.98 % | 11,864 | -11,855 | 43,008 | 1.10e-5 | 0.057 % | -2,602 / 2,607 |
| `cls_ct1` (8) | 99.77 % | 130.8 | -8.5 | 686 | 7.98e-3 | 24.5 % | -1.8 / 45.2 |
| `cls_ct2` (8) | 99.77 % | 152.3 | +93.8 | 950 | 9.30e-3 | 40.4 % | +347 / 363 |
| `cls_ft1` (8) | 99.21 % | 138.6 | +29.4 | 688 | 8.46e-3 | 32.9 % | +272 / 300 |
| `cls_ct1z` (8) | 99.38 % | 130.8 | -8.5 | 686 | 7.98e-3 | 24.5 % | -4.4 / 42.5 |
| `cls_ft1z` (8) | 96.54 % | 117.4 | -18.1 | 628 | 7.16e-3 | 22.1 % | -8.9 / 33.6 |
| `cls_ct1z2` (8) | 98.61 % | 27.2 | -7.9 | 112 | 1.66e-3 | 5.25 % | -2.5 / 9.4 |

Bias over b >= 0 and the zero-product counts: `approx/results/wang2026_error.md`. For
comparison: `park_14z` MRED 0.18 %, `r256_8z` 0.18 % (16 bits); `park_5z` 3.1 %, `r256_6z`
5.1 % (8 bits). RTL == model: `mulbench_check` exhaustive at N = 8 and 1,000,000 random + 4,096
corner pairs at N = 16, all equal; chip variants exhaustive in `approx/results/variants_error.md`.

## 5. Hardware (`syn/mulbench/results/table_w16.md`, `table_w8.md`)
Same bench and flow as `park_2023_r4.md` s.5 (DC topographical ss at 2.5 ns and 4.0 ns, tight
1.2 ns / 1.0 ns for the a -> p delay and min period, Formality vs the 2.5 ns netlist, SDF GLS +
PrimePower tt, 20,000 signed multiplies per stimulus, `mul_core` cells only; energy/op = power
x 2.5 ns).

**N = 16** (vs DesignWare `s_exact`; in brackets vs the exact radix-4 / 4:2 twin `park_0`):

| Design | area @2.5 ns (um^2) | @4.0 ns | a->p delay | min period | power uniform (mW) | power GAN-like (mW) | energy/op uniform / GAN (pJ) |
|---|---|---|---|---|---|---|---|
| `s_exact` | 2,132 | 1,892 | 1.056 ns | 1.472 ns | 0.880 | 0.788 | 2.20 / 1.97 |
| `park_0` (twin) | +38.1 % | +38.2 % | +26.4 % | +18.4 % | +87.1 % | +8.3 % | 4.12 / 2.13 |
| `cls_ct1` | +2.5 % (-25.7) | **-7.1 %** (-32.8) | +25.7 % (-0.5) | +18.5 % | +10.5 % (-40.9) | **-35.6 %** (-40.4) | 2.43 / 1.27 |
| `cls_ct2` | +1.3 % (-26.7) | **-9.7 %** (-34.6) | +25.9 % (-0.4) | +18.4 % | +9.8 % (-41.3) | **-28.7 %** (-34.1) | 2.42 / 1.41 |
| `cls_ft1` | **-12.9 %** (-37.0) | **-23.4 %** (-44.6) | +20.1 % (-4.9) | +14.0 % | **-10.7 %** (-52.3) | **-43.5 %** (-47.8) | 1.96 / 1.11 |
| `cls_ct1z` | +4.1 % (-24.7) | **-7.1 %** (-32.8) | +25.5 % (-0.7) | +19.2 % | +8.9 % (-41.8) | **-35.4 %** (-40.3) | 2.40 / 1.27 |
| `cls_ft1z` | **-12.1 %** (-36.4) | **-22.3 %** (-43.8) | +17.2 % (-7.3) | +13.6 % | **-0.9 %** (-47.1) | **-41.5 %** (-46.0) | 2.18 / 1.15 |
| `cls_ct1z6` | +17.5 % (-14.9) | +12.4 % (-18.7) | +25.7 % (-0.5) | +18.4 % | +34.4 % (-28.2) | **-21.2 %** (-27.2) | 2.96 / 1.55 |
| `tacbm_12` | **-3.8 %** | **-10.1 %** | +9.1 % | +7.3 % | +2.4 % | **-41.2 %** | 2.25 / 1.16 |

**N = 8** (vs `s_exact` 497 um^2, 0.782 ns, 0.228 / 0.209 mW; paper Table VII in brackets):

| Design | area @2.5 / @4.0 ns | delay / min period | power uniform / GAN-like | MRED |
|---|---|---|---|---|
| `cls_ct1` | -21.3 / -22.0 % (paper -25.6) | -8.1 / -4.4 % (paper -74.9) | -24.9 / -61.2 % (paper -20.9) | 24.5 % |
| `cls_ct2` | -26.0 / -26.6 % (-34.9) | -10.7 / -6.4 % (-75.3) | -24.9 / -55.9 % (-29.6) | 40.4 % |
| `cls_ft1` | -24.7 / -26.4 % (-37.9) | -5.1 / -3.1 % (-75.3) | -27.7 / -61.4 % (-32.9) | 32.9 % |
| `cls_ct1z` | -20.0 / -21.0 % | -8.7 / -4.7 % | -22.6 / -60.9 % | 24.5 % |
| `cls_ft1z` | -24.6 / -25.4 % | -7.3 / -4.2 % | -26.9 / -63.4 % | 22.1 % |
| `cls_ct1z2` (chip variant) | -6.7 / -9.3 % | -0.8 / +0.7 % | -1.3 / -49.6 % | 5.25 % |

Formality: SUCCEEDED for all 13 netlists. GLS products == model for all 26 power runs
(`approx/mulbench_gls.py`).

### Reading
- **At 8 bits the paper's area / power trend reproduces** (-21 to -26 % area, -25 to -28 %
  uniform power vs DesignWare; paper -26 to -38 / -21 to -33 %); its -75 % delay does not (ours
  -5 to -11 %: the paper's exact multiplier at 2.59 ns is evidently not a timing-driven
  DesignWare build). But these savings are bought with MRED 25-40 %, ten times the printed
  value: the designs are not "high-fidelity" at 8 bits.
- **At 16 bits the hand-written Booth overhead (+38 % area for `park_0`) is mostly recovered
  only by ABMFT1**: `cls_ft1` -12.9 % area (-23 % at 4.0 ns), -10.7 % uniform power, -43.5 %
  GAN-like power, MRED 1.0 % (`cls_ft1z`: same area, uniform power flat, MRED 0.68 %).
  ABMCT1 / 2 are area- and uniform-power-neutral to worse at 2.5 ns (better at 4.0 ns) with
  only GAN-like power gains. The 6-column band (MRED 0.16 %) is +17.5 % area.
- **Every cls design is slower**: a->p delay +17 to +26 %, min period +14 to +19 % (the exact
  upper half is the hand-written Booth / 4:2 tree, `park_0` +26 %; the band adds no serial
  stage beyond it: `cls_ct1` vs `park_0` -0.5 %). All still meet 400 MHz with > 0.7 ns slack.
- **vs `park_14z` (paper A) at equal or better accuracy**: `park_14z` (MRED 0.18 %) is -14.0 %
  area, -13.5 % uniform, -50.9 % GAN-like power, +6.1 % delay; `cls_ft1z` (MRED 0.68 %, 4x
  worse) is -12.1 % / -0.9 % / -41.5 % / +17 %. CLS is dominated. `tacbm_12` (Aizaz & Khare,
  MRED 0.057 %, the most accurate approximate row) is -3.8 % area, -41 % GAN-like power, +9 %
  delay, uniform power +2.4 %; it beats every cls design on accuracy and delay.

## 6. Verdict (16 bits, 400 MHz, vs `s_exact`)
| Variant | >= 1 positive hardware metric? | which |
|---|---|---|
| `cls_ct1` (ABMCT1) | yes | GAN-like power -35.6 % (area -7.1 % at 4.0 ns only); area +2.5 %, uniform +10.5 %, delay +26 % |
| `cls_ct2` (ABMCT2) | yes | GAN-like power -28.7 % (area -9.7 % at 4.0 ns); uniform +9.8 %, delay +26 %, MRED 1.5 % |
| `cls_ft1` (ABMFT1) | yes | area -12.9 %, uniform power / energy -10.7 %, GAN-like -43.5 %; delay +20 %, MRED 1.0 %, a x 0 != 0 |
| `cls_ct1z` | yes | GAN-like power -35.4 %; area +4.1 % |
| `cls_ft1z` | yes | area -12.1 %, GAN-like -41.5 %, uniform -0.9 %; delay +17 %, MRED 0.68 % |
| `cls_ct1z6` | yes, one | GAN-like power -21.2 % only (area +17.5 %, uniform +34 %) |

The designs are signed-native and add no serial stage beyond the exact radix-4 tree, so each
keeps a GAN-like power gain, and ABMFT1 also gains area and uniform power. None is
competitive: `park_14z` is better on every metric at 4x lower MRED, and the paper's own
8-bit accuracy is 10x worse than printed. Zero products: none of the paper's designs gives
a x 0 = 0; the `z` fix makes b = 0 exact (0 x b stays wrong).

**8-bit chip variants** (bench smoke test `run_bench.sh <v> --n 16`, result files not
committed): `cls_ct1z` (the paper's ABMCT1 + zero fix): RTL == Python emulation 16/16, PSNR
8.8 dB vs golden, labels 10/16 (MRED 24.5 % is unusable); `cls_ct1z2` (2-column band):
RTL == emulation 16/16, PSNR 19.5 dB, labels 16/16, area -6.7 %, GAN-like power -50 %
(park_5z: 29.2 dB, r256_6z: 25.5 dB).

## 7. Reproduce
```
python3 -m src_gan_tsmc65.approx.paper_wang2026 --jobs 40    # Tables II-VII, CLS, designs (~40 min)
python3 -m src_gan_tsmc65.approx.mulbench --width 16          # RTL (also --width 8)
python3 -m src_gan_tsmc65.approx.mulbench_check --width 16    # RTL == model
python3 -m src_gan_tsmc65.approx.gen                          # bench/variants/cls_ct1z*.v
src_gan_tsmc65/syn/mulbench/start.sh w16_cls.log 16 4 cls_ct1 cls_ct1z cls_ct1z6 cls_ft1 cls_ft1z cls_ct2 tacbm_12
src_gan_tsmc65/syn/mulbench/start.sh w8_cls.log 8 4 cls_ct1 cls_ct1z cls_ct1z2 cls_ft1 cls_ft1z cls_ct2
python3 -m src_gan_tsmc65.approx.mulbench_table --width 16    # after copying the summaries
```
Seven 16-bit and six 8-bit designs (four in parallel) took about 1.5 h on the server.
