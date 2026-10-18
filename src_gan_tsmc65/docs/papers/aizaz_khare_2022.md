# Aizaz & Khare 2022: truncated Booth multipliers with approximate carry compensation (TACBM)

Z. Aizaz and K. Khare, "Area and Power Efficient Truncated Booth Multipliers Using Approximate
Carry-Based Error Compensation", IEEE TCAS-II 69(2):579-583, 2022.

## 1. What the paper proposes
- **Truncation factor w** (Sec. II, Fig. 2(b)): a signed N x N radix-4 Booth multiplier
  (N = 16 in the paper) whose w least significant partial-product columns are not generated.
  Product bits 0 .. w-1 are 0 (Fig. 2(b), w = 10: columns #1-#10 truncated, 2N - w kept).
- **Approximate compensation carries t^k_w** (Steps 1-4, Table II, eqs. 1-5): the partial
  products P_{i,j} of the most significant truncated column (w-1; P_{i,j} = bit j of Booth row
  i, at column 2i + j) are added with the carry C_{w-1} of the columns below in a truth table;
  its second bit C_w is mapped on 4 x 4 k-map blocks, and bits are flipped so that the result no
  longer depends on C_{w-1}. Each block area becomes one term; terms of one w are mutually
  exclusive, and each is fed as one extra bit into column w. Published terms: w = 4 (1 term,
  t^1_4 = P_{0,3}, no gate), 6 (1), 8 (2), 10 (3), 12 (4); w = 14 is in Table IV but its terms
  are not given.
- **neg-OR** (Fig. 2(b) caption): "the neg terms [7] and the preceding partial product are ORed
  together" (black squares at columns 2i): the Booth +1 bit neg_i and the row's first bit
  P_{i,0} become one bit P_{i,0} | neg_i, an error of -2^(2i) when both are 1.
- The kept matrix is reduced with exact compressors / adders and a CLA. Error metrics come from
  10 M uniform random signed 16-bit pairs (MATLAB); synthesis in a 16 nm library (Table IV).
  For 8 bits the paper only states that the w = 4, 6, 8 circuits carry over, with 28 % area and
  36.9 % energy savings and "MRED of 0.02" at w = 6.

## 2. Reproduction (`src_gan_tsmc65/approx/`)
| File | Role |
|---|---|
| `tacbm.py` | truncated Booth matrix for any n and w, terms t^k_w of eqs. (1)-(5) (any subset), neg-OR, optional constant compensation; `tacbm(n, w, terms)` builds the multiplier (Python model + netlist) |
| `booth.py` | Booth encoder; new `strict_neg` option (digit 111 gives neg = 0, see below) |
| `metrics.py`, `exhaustive.py` | ERMS, NoEB (= 2N - log2(1 + ERMS)), PRED (P(RED < 2 %)); `signed_stats` (exhaustive or uniform random signed operands) |
| `paper_ak2022.py` | Table III / IV comparison -> `approx/results/ak2022_error.md` |
| `variants.py`, `gen.py` | the signed 8-bit `booth_trunc5` and `booth_akc` (`bench/variants/*.v`) |

Two choices the paper leaves open, both settled by the error numbers:
- **Booth encoder for the neg-OR.** With neg = b_{2i+1} (digit 111 = "-0", rows of ones + 1,
  as in `booth_exact`) the neg-OR alone gives NMED 0.763e-5 and MRED 0.101 %, against the
  paper's 0.507e-5 / 0.011 % for w = 4 (where truncation is almost free). With neg = 0 for
  digit 111 (`strict_neg`) it gives 0.509e-5 / 0.0115 %, so the paper's encoder is the strict
  one. At w <= 8 the neg-OR, not the truncation, sets the error (row 7 errs by 2^14).
- **Which bits are truncated.** w counts truncated columns (0 .. w-1, product bits 0 .. w-1 =
  0); the terms use the bits of column w-1 and enter column w (t^1_4 "fed to the 5th column").

## 3. Error metrics vs the paper (16-bit signed, 10 M uniform random pairs)
`python3 -m src_gan_tsmc65.approx.paper_ak2022` (full table incl. all Table III subsets in
`approx/results/ak2022_error.md`). NMED = MED / 2^30.

| w (all terms) | MRED % ours / paper | NMED 1e-5 ours / paper | NoEB ours / paper | PRED % ours / paper |
|---|---|---|---|---|
| 4 | 0.012 / 0.011 | 0.509 / 0.507 | 18.85 / 18.85 | 99.95 / 99.96 |
| 6 | 0.012 / 0.012 | 0.512 / 0.551 | 18.85 / 18.85 | 99.94 / 99.94 |
| 8 | 0.013 / 0.014 | 0.529 / 0.567 | 18.83 / 18.83 | 99.94 / 99.93 |
| 10 | 0.021 / 0.023 | 0.621 / 0.619 | 18.73 / 18.72 | 99.90 / 99.86 |
| 12 | 0.056 / 0.041 | 1.105 / 0.839 | 18.18 / 18.47 | 99.73 / 99.81 |

- **w = 4 .. 10 reproduce the paper**: NoEB within 0.01 bit, PRED within 0.04 points, MRED
  within 10 %, NMED within 7 % (w = 4 and 10 within 0.4 %).
- **w = 12 does not** (+37 % MRED, +32 % NMED). Truncation alone matches the paper ("0(w=12)":
  NMED 1.335 vs 1.342), and so do the single terms t^2, t^3, t^4 (1.292 / 1.281 / 1.331 vs 1.302 /
  1.281 / 1.338). Only t^1_12 (eq. 5) gains half of what the paper reports (1.207 vs 1.085), and
  the paper's combinations are not consistent with its single terms: the terms are mutually
  exclusive, so their gains should add up (ours do, within 0.002), but the paper's
  {t1..t4} = 0.839 is 0.14 below the sum of its single-term gains, and t^4 is worth 0.004 alone
  but 0.118 on top of {t1, t2, t3}. Fig. 3(c) draws t^1_12 differently from eq. (5)
  ((P_{3,5} + P_{4,3} P_{5,1})(P_{0,11} + P_{1,9} + P_{2,7})); that reading is no closer
  (NMED 1.202 alone, 1.100 with the other terms, 2 M samples). We keep eq. (5); without the
  authors' model the w = 12 gap cannot be closed.
- The subset rows of w = 8 / 10 are up to 38 % (MRED) and 21 % (NMED) below the paper (we lose less without the terms);
  the paper's "0(w=10)" (0.864) is also out of line with its own "0(w=12)" (1.342): truncation
  error grows about 4x per 2 columns (ours: 0.171 -> 0.826 above the w = 0 floor; paper: 0.357 -> 0.835).
- 8-bit (exhaustive, `strict_neg`, neg-OR): w = 6 gives MRED 7.08 % (NMED 3.65e-3, bias -58.6);
  the paper's "MRED of 0.02" for w = 6 is not reproduced (ours 0.071; w = 4 gives 0.024, so the
  paper's figure may belong to w = 4 or to a different 8-bit setup; it gives no details).
  Even pure truncation at w = 6 without the neg-OR gives MRED 10.0 %: in 8 bits the 6 truncated
  columns are almost half of the product.
- Hardware numbers of the paper (16 nm, 16-bit standalone) are not reproduced; the comparison
  here is the in-chip one of section 5.

## 4. Student variants (signed 8 x 8, `gan_mul8`)
- `booth_trunc5`: `booth_exact` (same encoder, same rows) with columns 0 .. 4 not generated
  (row bits and neg_0, neg_1, neg_2) and a constant 1 in column 5. **Choice of constant.** The
  course wording "replaced by '10000'" / "replaced with '1'" puts a 1 in column 4 (+16, the
  half-LSB rounding constant). The paper never keeps bits below w: the truncated part acts only
  through carries into column w, and TACBM approximates exactly that carry. The constant
  version of this is a fixed carry C_5 = 1 (+32), and the data agree: the truncated part
  averages 44.25 (all inputs and b >= 0), so +32 (bias -12.25) is closer than +16 (bias -28.25).
  Product bits 0 .. 4 are 0.
- `booth_akc`: TACBM at the paper's 8-bit point w = 6: columns 0 .. 5 not generated,
  t^1_6 = P_{0,5} | P_{1,3} P_{2,1} (eq. 2, 2 gates) into column 6, neg-OR with the strict
  encoder, exact Dadda tree (11 FA + 7 HA vs 15 FA + 9 HA in `booth_exact`).
- Both: exact Dadda tree and one `+`, RTL == Python on all 65,536 inputs
  (`approx/results/variants_error.md`).

| Variant | MAE / bias, all | MAE / bias, b >= 0 | max abs error | error rate | MRED |
|---|---|---|---|---|---|
| `booth_trunc5` | 19.95 / -12.25 | 19.95 / -12.25 | 64 | 95.1 % | 4.12e-2 |
| `booth_akc` | 59.83 / -58.62 | 44.36 / -42.62 | 192 | 98.4 % | 7.08e-2 |

**Zero activations.** A constant compensation adds +32 even when the exact product is 0, and
most activations of the generator are 0 after the ReLU. So the expected-value argument fails
in this chip: on the 256-latent benchmark (Python emulation of the chip) constant 0 gives
11.6 dB PSNR, 16 gives 7.1 dB, 32 gives 6.3 dB and 48 gives 6.0 dB. `booth_akc` keeps exact
zeros (b = 0 makes all Booth rows and t^1_6 zero), which is why it beats `booth_trunc5` in
quality despite a 5x larger MAE.

## 5. Results in the chip
Full rows in `docs/results.md` s.5 (DC ss 2.4 ns, PT and PrimePower tt SDF at 2.5 ns = 400
MHz; FID from 10,000 RTL images; delays from the 1.8 ns netlists at 2.0 ns). Percentages:
vs DC's `a * b` (`exact`) / vs `booth_exact`.

| Variant | PSNR (dB) / labels | FID-10k | 16 x mul8 area | mul8 power (SDF) | Energy/image | Min period | mul8 delay |
|---|---|---|---|---|---|---|---|
| exact (`a * b`) | inf / 100 % | 78.65 | 9,890 um^2 | 0.192 mW | 51.72 uJ | 1.817 ns | 0.937 ns |
| booth_exact | inf / 100 % | 78.65 | 11,102 (+12.3 %) | 0.154 (-19.4 %) | 51.72 (-0.0 %) | 1.814 | 1.000 |
| booth_trunc5 | 6.31 / 39.1 % | 183.14 | 8,684 (-12.2 / -21.8 %) | 0.153 (-20.1 / -1.0 %) | 51.60 (-0.2 / -0.2 %) | 1.812 (-0.3 / -0.1 %) | 1.045 (+11.6 / +4.5 %) |
| booth_akc | 11.32 / 64.8 % | 133.62 | 7,621 (-22.9 / -31.4 %) | 0.094 (-50.8 / -39.0 %) | 50.88 (-1.6 / -1.6 %) | 1.816 (-0.0 / +0.1 %) | 0.996 (+6.3 / -0.5 %) |

- **Criterion (at least one better hardware metric): met by both**, against both baselines:
  both are smaller, lower in mul8 power, chip power and energy than `exact` and `booth_exact`.
  booth_akc is also faster than booth_exact in the multiplier (-0.5 %), booth_trunc5 has the
  lowest minimum period of the three. Neither is faster than DC's `a * b` multiplier.
- booth_akc halves the multiplier power: the 6 truncated columns remove 12 row bits, 3 neg bits
  and 4 FA + 2 HA, the neg-OR merges the last neg bit, and the compensation costs 2 gates. With the
  accumulator bits that DC removes (product bits 0-5 are constant 0), the chip saves 1.6 % energy,
  the largest saving here of any variant whose images are still recognisable.
- booth_trunc5 saves 22 % multiplier area but only 1 % SDF power vs booth_exact (7 % with zero
  delay). The truncation removes low-column cells; the timed (glitch) activity, which is
  probably concentrated in the unchanged higher columns, stays (not analysed further).
- Quality is poor for both. booth_akc has a bias of -43 per product at b >= 0, four times
  bw_axfa6 (FID 96.9). booth_trunc5's +32 on zero products (section 4) makes it the worst
  variant apart from evo_1KR3.
- FM SUCCEEDED (2.4 and 1.8 ns netlists), PT ss setup (+0.084 / +0.086 ns) and ff hold
  (+1.3 / +1.6 ps) pass at 2.5 ns, and GLS of seed_0 (zero delay and SDF) matches the emulation
  784/784 for both. 10,000/10,000 RTL images match the Python emulation.

## 6. Notes
- Regenerate: `python3 -m src_gan_tsmc65.approx.gen`, `python3 -m src_gan_tsmc65.approx.check`,
  `python3 -m src_gan_tsmc65.approx.paper_ak2022` (about 10 min on 40 cores).
- Hardware flow per variant: `syn/run_variant_flow.sh <v>`, plus zero-delay power
  `power/run_power.sh <v> --clock 2.5 --syn-period 2.4`.
