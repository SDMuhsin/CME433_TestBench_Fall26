# Venkatachalam & Ko 2017: approximate HA / FA / 4:2 compressor multipliers

S. Venkatachalam and S.-B. Ko, "Design of Power and Area Efficient Approximate Multipliers",
IEEE TVLSI 25(5):1782-1786, 2017.

## 1. What the paper proposes
- **Altered partial products** (eq. 1): in every column with more than three partial products,
  each pair a_{m,k}, a_{k,m} becomes p = a_{m,k} OR a_{k,m} and g = a_{m,k} AND a_{k,m}
  (exact, since x + y = (x | y) + (x & y)). The g's of a column are OR-ed, at most 4 per gate
  (the only approximation of the g's).
- **Approximate cells** (eqs. 2-4), each off by at most 1:
  half adder Sum = x1 | x2, Carry = x1 x2 (wrong for 11);
  full adder W = x1 | x2, Sum = W ^ x3, Carry = W x3 (wrong, by -1, iff x1 = x2 = 1);
  4:2 compressor with two outputs, Sum = (x1^x2) | (x3^x4) | x1x2x3x4, Carry = x1x2 | x3x4
  (wrong in 5 of 16 cases).
- **Multiplier1** approximates all columns, **Multiplier2** the n - 1 least significant ones.
  The paper draws the 8 x 8 reduction (Fig. 2) but reports synthesis and error numbers for
  n = 16 only (Tables V, VI).

## 2. Reproduction (`src_gan_tsmc65/approx/`)
| File | Role |
|---|---|
| `netlist.py` | bit-level netlist (AND / OR / XOR / NOT, constant folding); one description is both the Python model and the Verilog |
| `cells.py` | exact HA / FA and the paper's approximate HA / FA / 4:2 |
| `matrix.py`, `pp.py`, `booth.py` | partial-product matrices: unsigned AND array (Fig. 1 order), Baugh-Wooley, radix-4 Booth (generic n); negative-weight bits become inverted bits + one constant |
| `reduce.py` | Dadda-style column reduction with a cell set per column (sequence 2, 3, 4, 6, ... for FA; 2, 3, 6, 12, ... with 4:2) |
| `vk2017.py` | the paper's Multiplier1 / Multiplier2 for any n |
| `variants.py`, `gen.py`, `emit.py` | signed `gan_mul8` variants, Verilog writer (`bench/variants/*.v`, `approx/rtl/vk2017_m{1,2}_u8.v`) |
| `metrics.py`, `exhaustive.py` | ER, MED, NMED, NED, MRED, bias, max error (chunked, parallel, exhaustive up to n = 16) |
| `check.py`, `paper_vk2017.py` | RTL == Python check (65,536 inputs) and the paper-metric table |

The 8 x 8 Multiplier1 has exactly the structure of Fig. 2: stage 1 uses 3 approximate HA, 3 FA
and 3 compressors (columns 4-12) plus OR2 x4, OR3 x4, OR4 x1 for G3..G11; stage 2 uses 1 HA
and 11 FA; an exact adder adds the two rows. The planner derives this from the Dadda rule and
the drawing order of Fig. 1, except one operand order: Fig. 2 draws column 12 of stage 2 as
S12, C11, a6,6, while the generic rule gives S12, a6,6, C11. The order matters because x3 is the
exact input of the approximate FA (MED 1,677 with the drawn order, 1,781 with the rule). The
8-bit model follows the drawing (`vk2017.fig2_order`).

## 3. Error metrics vs the paper (exhaustive, unsigned)
`python3 -m src_gan_tsmc65.approx.paper_vk2017` (all 2^16 / 2^32 operand pairs; full table in
`approx/results/vk2017_error.md`). MRED = mean |ED| / product over non-zero products;
NMED = MED / (2^n - 1)^2. The paper's "NED" matches NMED (normalising by the largest error
instead gives about 0.1 for every design).

| Design | n | ER | MRED (ours / paper) | NMED (ours / paper "NED") | bias | max abs ED |
|---|---|---|---|---|---|---|
| Multiplier1 | 8 | 81.8 % | 7.92e-2 / - | 2.58e-2 / - | -1,424 | 17,948 |
| Multiplier2 | 8 | 59.8 % | 6.59e-3 / - | 5.83e-4 / - | -36.8 | 380 |
| Multiplier1 | 16 | 99.8 % | 9.21e-2 / 7.63e-2 (+21 %) | 2.76e-2 / 1.78e-2 (+55 %) | -8.1e7 | 1.17e9 |
| Multiplier2 | 16 | 97.6 % | 2.22e-4 / 2.44e-4 (-9 %) | 5.89e-6 / 7.10e-6 (-17 %) | -2.5e4 | 229,884 |

- **Multiplier2 reproduces the paper** within 9 % (MRED) and 17 % (NED), with the same order of
  magnitude and ranking. Its error comes only from the 15 low columns, so it depends little on
  how the tree is built.
- **Multiplier1 is in the right range but higher** (+21 % MRED, +55 % NED). The paper does not
  give the 16-bit tree. Ours follows the 8-bit rules (alteration in columns with more than
  3 bits, OR groups of at most 4 split evenly, Dadda stages 6, 3, 2 with 4:2 compressors first,
  operands in Fig. 1 order). In Multiplier1 every column is approximate, and NED is dominated
  by the high columns, where the stage count and which bits meet in an approximate FA (x1 = x2
  = 1 is the error case) set the error. The 8-bit sensitivity shows how much this matters:
  swapping the two inputs of one FA (column 12, see above) changes MED by 6 %. A tree with
  more stages, or one that routes the high-probability p signals into x3, would lower our
  figure. Without the authors' tree, this gap cannot be closed with certainty.
- The paper's synthesis numbers (Table V, 16-bit, standalone, typical corner) are not
  reproduced; the hardware comparison here is the in-chip one of section 5.

## 4. Student variants (signed 8 x 8, `gan_mul8`)
- `bw_axfa6`: Baugh-Wooley AND array (inverted sign-row bits + constant 2^8 + 2^15), Dadda tree
  (stages 6, 4, 3, 2), approximate HA / FA in columns 0-5 (6 vk_fa + 4 vk_ha of 42 cells), one
  `+` for the final adder.
- `booth_axfa5`: radix-4 Booth, b (activation) recoded into 4 digits, rows of 9 bits plus the
  neg bit at column 2i, sign extension by one constant; Dadda tree (stages 4, 3, 2), approximate
  HA / FA in columns 0-4 (1 vk_fa + 3 vk_ha of 24 cells).
- `bw_exact`, `booth_exact`: the same dot diagrams with exact cells (bit-exact).
- No altered partial products or 4:2 compressors in the student variants (the course asks for
  the HA / FA only). Column bits are listed by multiplier row; the first bits of a column go
  into the cells, so x3 of an approximate FA is the third bit.
- RTL == Python on all 65,536 inputs for all four (`approx/results/variants_error.md`).

| Variant | MAE / bias, all | MAE / bias, b >= 0 | max abs error | error rate | MRED |
|---|---|---|---|---|---|
| `bw_axfa6` | 12.85 / -10.81 | 12.85 / -10.81 | 100 | 45.0 % | 2.23e-2 |
| `booth_axfa5` | 6.56 / +0.25 | 6.56 / +0.25 | 28 | 53.0 % | 1.17e-2 |

The approximate FA is always off by -1 and the HA by +1; Baugh-Wooley's low columns are
FA-heavy, so `bw_axfa6` has a bias of about -11 per product, comparable to `example_trunc4`
(-6.5). The Booth tree's low columns are HA-heavy (3 HA, 1 FA), so the errors cancel (bias +0.25).

## 5. Results in the chip
Full rows in `docs/results.md` s.5 (DC ss 2.4 ns, PT and PrimePower tt SDF at 2.5 ns = 400
MHz; FID from 10,000 RTL images; delays from the 1.8 ns netlists at 2.0 ns). Percentages:
vs DC's `a * b` (`exact`) / vs the structured exact baseline of the same architecture.

| Variant | PSNR (dB) / labels | FID-10k | 16 x mul8 area | mul8 power (SDF) | Energy/image | Min period | mul8 delay |
|---|---|---|---|---|---|---|---|
| exact (`a * b`) | inf / 100 % | 78.65 | 9,890 um^2 | 0.192 mW | 51.72 uJ | 1.817 ns | 0.937 ns |
| bw_exact | inf / 100 % | 78.65 | 10,730 (+8.5 %) | 0.147 (-23.5 %) | 51.57 (-0.3 %) | 1.811 | 1.010 |
| bw_axfa6 | 21.56 / 92.2 % | 96.90 | 10,178 (+2.9 / -5.1 %) | 0.139 (-27.4 / -5.1 %) | 51.52 (-0.4 / -0.1 %) | 1.810 (-0.4 / -0.1 %) | 1.004 (+7.1 / -0.6 %) |
| booth_exact | inf / 100 % | 78.65 | 11,102 (+12.3 %) | 0.154 (-19.4 %) | 51.72 (-0.0 %) | 1.814 | 1.000 |
| booth_axfa5 | 32.31 / 98.0 % | 78.31 | 10,886 (+10.1 / -1.9 %) | 0.148 (-22.6 / -4.1 %) | 51.59 (-0.3 / -0.2 %) | 1.813 (-0.2 / -0.1 %) | 0.985 (+5.1 / -1.6 %) |

- **Criterion (at least one better hardware metric): met by both approximate variants**, against
  both baselines. Against their structured exact twin they are smaller, lower-power, lower-energy
  and faster in the multiplier. Against DC's `a * b` they win on mul8 power, chip power, energy
  and minimum period, and lose on mul8 area and mul8 delay.
- The large mul8 power gap to `a * b` comes from the structure, not the approximation: the
  exact gate-level trees already use 19-24 % less multiplier power (zero delay: 0.116 / 0.126 vs
  0.187 mW, with 15-16 % lower leakage) at 9-12 % more area. DC's DesignWare multiplier
  is faster (a -> p 0.937 vs 1.00 ns), so it is probably built from larger, leakier cells; this was not analysed further. Chip-level gains stay below 0.5 %,
  because the multipliers are only about 2 % of chip power (section 5 of results.md).
- Quality: `booth_axfa5` is the better design here, with an unbiased error (+0.25), FID 78.31
  (exact 78.65) and 98 % label agreement. `bw_axfa6` has a -10.8 bias on every product, which
  layers 2-3 accumulate over 256 non-negative activations: FID 96.9, worse than trunc4 (87.0).
- FM SUCCEEDED and GLS (zero-delay and SDF, seed_0) matches the emulation 784/784 for all four.
  PT ss setup passes for all four. ff hold passes except bw_axfa6 (-4.4 ps, 8 endpoints
  `u_seq/u_rq/q_reg_*` -> `u_seq/rq_res_reg_*`): this is the known direct Q -> D residue of
  results.md s.2, outside the multiplier, left to the P&R hold fix.

## 6. Notes
- Every design choice above that the paper leaves open (n = 16 tree, Multiplier2's exact
  part, the OR grouping for more than 4 g's) is in `vk2017.py` / `reduce.py` docstrings.
- Regenerate everything: `python3 -m src_gan_tsmc65.approx.gen`, then
  `python3 -m src_gan_tsmc65.approx.check` and `python3 -m src_gan_tsmc65.approx.paper_vk2017`.
