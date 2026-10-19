# Amirafshar et al. 2023: carry-disregard approximate multipliers (CDM)

N. Amirafshar, A. S. Baroughi, H. S. Shahhoseini, N. TaheriNejad, "Carry Disregard Approximate
Multipliers", IEEE TCAS-I 70(12):4840-4853, 2023, doi:10.1109/TCSI.2023.3306071.

## 1. What the paper proposes

- **Split** (eq. 1, Fig. 2): an unsigned 8 x 8 array multiplier is built from two 8 x 4 array
  multipliers, group A = A x B_L and group B = A x B_H, which run in parallel and are added by
  one exact CLA.
- **Carry disregard** (Sec. IV, Figs. 3-4): in the 8 x 4 multiplier cd_x the carries of
  columns 2 .. x (1-based, column k holds a_i b_j with i + j = k - 1) are not generated. Those
  columns become independent: each cell is an AND plus an XOR (PPU1, no carry in or out); at the
  boundary column the paper uses half-adder (PPU2) and two-AND full-adder (PPU3) cells without a
  carry input, the rest are exact cells. cd_2 .. cd_a (x = 2 .. 10) are drawn; cd_1 = exact.
- **CDM8_xy** (Table I) = cd_x in group A, cd_y in group B (hex digits): 44, 51 (= cd_5 + exact,
  "50" in Table I), 62, 73, 74, 84, 95, a6, a7, a8, a9, aa.
- **Error model** (eqs. 2-8): a column with L ones loses floor(L / 2) carries of weight 2^k, so
  ED = sum_k 2^k floor(L_k / 2) over the disregarded columns, ED_xy = ED_cdx + 2^4 ED_cdy. The
  result is always <= the exact product.
- **CDM16** (Fig. 5, Table II, eqs. 9-24): four CDM8s (A_L B_L, A_H B_L, A_L B_H, A_H B_H) and
  four 8-bit adders (CLAx) that drop their carry out; 14 designs CDM16_wxyz (digit -> CDM8:
  0 exact, 3 CDM8_40, 7 CDM8_84, 8 CDM8_95, b CDM8_a8, f CDM8_aa).
- Unsigned only. Metrics exhaustive in Python (Table III: MED, NMED = MED / (2^N - 1)^2,
  MRED, NoEB = 2N - log2(1 + RMSE), PC = share of exact outputs); synthesis with Genus on
  Nangate 45 nm (Tables IV-V); Gaussian smoothing case study (Fig. 7). Pareto designs: CDM8_51,
  62, 73, 74 (power, PDP); CDM8_95 has the lowest delay; the case study recommends CDM8_73 over
  CDM8_44 (same quality, cheaper) and finds everything up to CDM8_a7 usable (> 30 dB).

## 2. Reproduction (`src_gan_tsmc65/approx/`)

| File | Role |
|---|---|
| `cdm.py` | analytic model (`ed8x4`, `unsigned8` = eq. 8, `unsigned16` = Fig. 5 / eqs. 9-21, `signed8`), bit-level netlist (`matrix`: one XOR per disregarded group column, other partial products exact; `cdm(x, y, mode)`), the signed extension (`sign_magnitude`, `negate_if`) |
| `paper_cdm2023.py` | Table IV / V comparison and the gate-count trend -> `approx/results/cdm2023_error.md` |
| `variants.py`, `gen.py` | signed 8-bit `cdm_51`, `cdm_73`, `cdm_95` and the ablation `cdm_51b` (`bench/variants/*.v`) |

The netlist keeps the paper's function exactly (XOR columns, lost carries) but not its cell
layout: the exact remainder of both groups is one Dadda tree with one final `+` (as for every
structured variant here), not two ripple arrays and a CLA; DC restructures either. The 8-bit
netlist equals eq. 8 on all 65,536 inputs for all 13 designs (Table IV column below).

## 3. Error metrics vs the paper (`approx/results/cdm2023_error.md`)

`python3 -m src_gan_tsmc65.approx.paper_cdm2023` (exhaustive, like the paper; the 16-bit rows
take 15-25 min each on 40 cores). MRED over non-zero products, NMED = MED / (2^N - 1)^2.

| Paper table | Designs | Result |
|---|---|---|
| Table IV, CDM8 (2^16 pairs) | Exact8 + 12 CDM8s | MED, NMED, MRED, NoEB, PC equal to the printed digits for all 12 (largest gap: NoEB 3.37 vs 3.36 for a9, 2.86 vs 2.85 for aa, last-digit rounding) |
| Table V, CDM16 (2^32 pairs) | 14 CDM16s | MED / NMED within 0.2 % for 10 of 14 (all with the CLAx carries dominating), +0.8 / +3.1 / +6.0 / -0.4 % for fff8 / ffff / fffb / fff7; PC within 0.8 % for the first six, -2.6 to -9.6 % for the f... designs; MRED x1.94-2.20 and NoEB +0.46-0.51 bit for every row (see below) |

- The analytic error model of eqs. 3-8 is the whole design: the netlist with XOR columns
  equals `unsigned8` on all inputs for every CDM8, and the paper's figures follow from it.
- **CDM16 MRED / NoEB.** Already for CDM16_0000 (four exact 8-bit multipliers; the only error
  is the carry the CLAx drop), where MED (8,222,699.5 vs 8,222,699) and PC (19.61 %) agree to
  the printed digit, our MRED is 2.004x the paper's and our NoEB 0.50 bit higher (the paper's
  MSE is 2x ours). The same two factors appear in every row, so they are a convention of the
  paper's 16-bit script (its MRED and MSE normalised differently from its MED), not a property
  of the design; the 8-bit Table IV, computed the same way, agrees on all five metrics. The
  remaining MED / PC gaps of the designs built mostly from CDM8_aa (+6 % MED for fffb, -10 %
  PC) mean the paper's 16-bit composition differs slightly from Table II / Fig. 5 as we read
  them (which sub-multiplier sits where, or how the CLAx are chained); the eqs. 17-18 carry
  counts are implemented literally.
- **Hardware trend.** The paper's Nangate numbers are not reproduced (different library and a
  standalone multiplier). As a proxy, the gate count of our netlists (before the final adder)
  ranks the 13 designs like the paper's area (Spearman 0.995): CDM8_51 -9 % gates / -10.4 %
  paper area, CDM8_73 -25 / -21 %, CDM8_95 -43 / -33 %, CDM8_aa -58 / -48 %. In the chip,
  CDM8_51 on a two's-complement array (`cdm_51b`, section 5) has 11.8 % less mul8 area and
  10.9 % less mul8 power than its structured exact twin `bw_exact`; the paper reports -10.4 %
  area and -8.8 % power for CDM8_51 vs Exact8.

## 4. Student variants (signed 8 x 8, `gan_mul8`)

The paper names CDM8_51, 62, 73, 74 as its power / PDP Pareto designs, CDM8_95 as the fastest,
and recommends CDM8_73 in its image case study. The variants span that range: `cdm_51` (most
accurate), `cdm_73` (the case-study pick), `cdm_95` (lowest delay in the paper).

**Signed handling.** The paper is unsigned. A carry-disregard array on two's-complement
operands (`mode='bw'`: Baugh-Wooley array, carries disregarded among the a_i b_j, sign bits
exact) is cheap but one-sided: the bits of a small negative weight are dense ones, they lose
many carries, and every error is <= 0, so the bias equals -MAE (-14 / -89 / -281 for 51 / 73 /
95). In the golden model this gives 18.8 / 9.0 / 9.5 dB PSNR. The student variants therefore
use a sign-magnitude form with no carry chain (`cdm.sign_magnitude`): one's-complement
magnitudes a' = a xor a7, b' = b xor b7, the paper's CDM on a' x b', exact correction rows
a7 b' + b7 a' + a7 b7 (|a||b| = (a' + a7)(b' + b7)), and the product sign s = a7 xor b7 applied
inside the bit matrix (-V = sum (bit xor s) 2^k - s C, so every bit is XOR-ed with s and s
enters at the set bits of -C mod 2^16). The error is the paper's ED of the magnitudes with the
sign of the product: unbiased, and 0 for a zero operand. `cdm_51b` is the Baugh-Wooley form of
CDM8_51, kept as an ablation to separate the cost of the sign handling from the carry
disregard.

| Variant | Design | RTL == Python | MAE / bias, all | MAE / bias, b >= 0 | max abs error | error rate | MRED |
|---|---|---|---|---|---|---|---|
| `cdm_51` | CDM8_51, sign-magnitude | 65536/65536 | 14.25 / +0.00 | 14.25 / +0.00 | 108 | 40.4 % | 1.04 % |
| `cdm_73` | CDM8_73, sign-magnitude | 65536/65536 | 89.25 / +0.00 | 89.25 / +0.00 | 684 | 57.5 % | 4.02 % |
| `cdm_95` | CDM8_95, sign-magnitude | 65536/65536 | 281.25 / +0.00 | 281.25 / +0.00 | 2220 | 64.1 % | 8.75 % |
| `cdm_51b` | CDM8_51, Baugh-Wooley (ablation) | 65536/65536 | 14.25 / -14.25 | 14.25 / -14.25 | 108 | 40.4 % | 3.05 % |

(`python3 -m src_gan_tsmc65.approx.check`; zero products exact for all four, `zero_hits` = 0;
the sign-magnitude netlists also equal the analytic `cdm.signed8` on all inputs.) The MAE of
each signed variant equals the paper's unsigned MED of the same design (the magnitudes cover the
same 7-bit range for every sign).

## 5. Results in the chip

Full rows in `docs/results.md` s.5 (DC ss 2.4 ns, PT and PrimePower tt SDF at 2.5 ns = 400 MHz;
FID from 10,000 RTL images; minimum period and mul8 delay from the 1.8 ns netlists at 2.0 ns).
Percentages vs `exact` (DC's `a * b`); for `cdm_51b` also vs its structured twin `bw_exact`.

| Variant | PSNR (dB) / labels | FID-10k | 16 x mul8 area | mul8 power (SDF) | Chip power | Energy/image | Min period | mul8 delay |
|---|---|---|---|---|---|---|---|---|
| exact (`a * b`) | inf / 100 % | 78.65 | 9,890 um^2 | 0.192 mW | 8.816 mW | 51.72 uJ | 1.817 ns | 0.937 ns |
| bw_exact | inf / 100 % | 78.65 | 10,730 (+8.5 %) | 0.147 (-23.5 %) | 8.791 (-0.3 %) | 51.57 (-0.3 %) | 1.811 (-0.3 %) | 1.010 (+7.8 %) |
| cdm_51 | 30.32 / 94.9 % | 79.09 | 14,834 (+50.0 %) | 0.292 (+52.5 %) | 8.975 (+1.8 %) | 52.66 (+1.8 %) | 1.840 (+1.3 %) | 1.037 (+10.7 %) |
| cdm_73 | 23.96 / 87.5 % | 82.51 | 13,105 (+32.5 %) | 0.255 (+33.4 %) | 8.950 (+1.5 %) | 52.51 (+1.5 %) | 1.815 (-0.1 %) | 1.054 (+12.5 %) |
| cdm_95 | 20.44 / 80.1 % | 83.92 | 12,285 (+24.2 %) | 0.239 (+24.7 %) | 8.911 (+1.1 %) | 52.28 (+1.1 %) | 1.815 (-0.1 %) | 1.016 (+8.5 %) |
| cdm_51b | 18.81 / 87.9 % | 102.20 | 9,469 (-4.3 / -11.8 %) | 0.131 (-31.8 / -10.9 %) | 8.783 (-0.4 / -0.1 %) | 51.53 (-0.4 / -0.1 %) | 1.813 (-0.2 / +0.1 %) | 0.998 (+6.5 / -1.2 %) |

- **Criterion (at least one better hardware metric): not met by cdm_51, cdm_73, cdm_95; met by
  cdm_51b** (total area -0.2 %, mul8 area -4.3 %, chip power and energy -0.4 %, mul8 power
  -31.8 % vs exact; mul8 area -11.8 %, mul8 power -10.9 %, energy -0.1 % vs bw_exact).
  cdm_73 / cdm_95 have a 2 ps lower minimum period than exact (1.815 vs 1.817 ns); this is
  DC / PT noise on paths that do not run through the multiplier differently (their own mul8
  delay is +8.5 / +12.5 %), not a hardware gain, and is not counted.
- **Why the sign-magnitude CDMs cost more.** The carry disregard saves what the paper says it
  does (cdm_51b vs bw_exact: -11.8 % mul8 area, -10.9 % mul8 power, in line with the paper's
  -10.4 % / -8.8 % for CDM8_51). The sign handling costs more than that: in weighted 2-input gate
  units (XOR = 2.33, AND / OR = 1.33) the exact Baugh-Wooley netlist is 425, the same array in
  sign-magnitude form 637 (+50 %: 14 operand XORs, 15 correction ANDs and one XOR per matrix
  bit), against carry-disregard savings of 35 / 96 / 136 units for 51 / 73 / 95 in the unsigned
  core. Sign-magnitude CDM8_51 / 73 / 95 come to 585 / 507 / 464 units, all above the
  Baugh-Wooley exact array, and DC's result follows (+24 to +50 % mul8 area vs exact). The
  overhead is not timing pressure: at a relaxed 4.0 ns, cdm_73's 16 multipliers take 10,678
  um^2 against exact's 7,984 (+33.7 %, `results/syn_{exact,cdm_73}_ss_p4.txt`), the same ratio
  as at 2.4 ns. A cheaper exact conditional negation (one XOR per final-row bit, -2s in the
  matrix) was tried in the model and is larger still (289 vs 279 gates for CDM8_73).
  Folding the correction into the operands does not help either: any unbiased form has to
  apply the product sign to the disregarded columns, which are the approximate part.
- **Quality.** Sign-magnitude keeps the error unbiased, and the FIDs follow the MAE:
  cdm_51 79.09 (exact 78.65, PSNR 30.3 dB, 94.9 % labels), cdm_73 82.51, cdm_95 83.92, all better
  than example_trunc4 (87.0) and bw_axfa6 (96.9). The Baugh-Wooley ablation cdm_51b has the same
  MAE as cdm_51 but its -14.25 bias per product costs 23 FID (102.20, 18.8 dB), in line with the
  bias-to-FID relation of the truncated Booth variants. The paper's Gaussian-smoothing ranking
  (51 > 73 > 95, all usable) carries over to the GAN.
- **Timing / equivalence.** FM SUCCEEDED for all four (2.4 and 1.8 ns netlists); PT ss setup at
  2.5 ns +0.082..+0.088 ns, all meet 500 MHz on the 1.8 ns netlists (WNS +0.160..+0.187 ns).
  ff hold: cdm_95 +1.2 ps and cdm_51b +0.8 ps pass; cdm_51 (-6.1 ps, 7 endpoints) and cdm_73
  (-5.3 ps, 8 endpoints) miss it on `u_seq/u_rq/q_reg_*` -> `u_seq/rq_res_reg_*` only, the direct
  Q -> D residue outside the multiplier already seen for bw_axfa6 (left to the P&R hold fix).
  GLS of seed_0 (zero delay and SDF) matches each variant's emulation 784/784, and
  10,000/10,000 RTL images match the Python emulation for all four.
- Zero-delay power: cdm_51 8.846, cdm_73 8.815, cdm_95 8.786, cdm_51b 8.661 mW (exact 8.741,
  bw_exact 8.675); mul8 0.264 / 0.229 / 0.213 / 0.102 mW (exact 0.187, bw_exact 0.116).

## 6. Notes

- The 16-bit Table V sweep (14 x 2^32 pairs of the numpy model) took about 4.5 h (nice 19) on 40 cores
  while the RTL runs shared the machine.
- Paper Table I labels the cd_5 / exact design "CDM8_50", Table IV and the text "CDM8_51";
  Table II and Fig. 7 use "CDM8_40" for cd_4 / exact. cd_0 and cd_1 are both the exact 8 x 4
  multiplier (column 1 has no carry), so these are the same designs.
