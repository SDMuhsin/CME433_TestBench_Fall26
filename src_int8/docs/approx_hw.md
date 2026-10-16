# Approximate INT8 multipliers: 65 nm hardware characterisation (phase B2)

This page measures the standalone `mq_mul8` variants of `docs/approx_cssm.md` on the 65 nm
library of the `src_int8_tsmc65` flow. It sets the hardware savings against the LM cost from
the emulator screen, and recommends what to carry into the phase C benchmark.

All numbers come from `src_int8/approx/results/`. Those files are the summary files of the
server runs, one per run, named `syn_<tag>.txt` and `pwr_<tag>_<vec>[_zd].txt`.
`results/hw_tables.md` holds every table, produced by `syn/collect.py`.

## 1. Designs

| Variant | What it is | Emulator dBPB (512 crops) |
|---|---|---:|
| `exact` | `a * b` in `rtl/int/mq_mul8.v`, optimised by DC with DesignWare (the chip's multiplier) | 0 |
| `exact_dadda` | structural Baugh-Wooley + Dadda tree (`bench/variants/exact_dadda.v`), the papers' type of exact baseline | 0 |
| `cssm CSSM_M=5/6/7` | signed C-SSM, Strollo et al., TCAS-I 2022 (`bench/variants/cssm.v`) | +0.78 / +0.072 / +0.010 |
| `ilm` | ILM-0 (exact adders), Ansari, Cockburn, Han, IEEE TC 70(4), 2021 (`bench/variants/ilm.v`, new) | +0.066 |

### ILM reproduction (`bench/variants/ilm.v`, `approx/ref/ilm.py`)

The IEEE TC paper is not open access. The design was reproduced from the same work in
M. S. Ansari's PhD thesis (University of Alberta, 2019), Sec. 5.2: Algorithm 2, Fig. 5.3 and
Tables 5.4 and 5.6.

The design:

- **Nearest-one detector.** Each operand X becomes 2^k + q, where 2^k is the nearest power of
  two. It uses an up-rounding stage (`T[i+1] = 1` when `X[i]` and `X[i-1]` are both 1, so ties
  round up) followed by a leading-one detector. Following the paper, there is no up-rounding
  beyond 2^7.
- **Product.** A*B ~ 2^(k1+k2) + q1 2^k2 + q2 2^k1. The q1 q2 term is dropped, which gives a
  two-sided error.
- **Signed INT8.** Sign-magnitude around the unsigned core, as in the paper's NN use. The
  result is 0 when either operand is 0. Magnitudes are at most 128, so the 2^7 cap never
  applies.

Checks:

- **RTL vs reference model.** The RTL equals `ref/ilm.py` on all 65,536 signed inputs
  (`err/run.py ilm --ref ilm`, 0 mismatches) and on all 65,025 unsigned core inputs.
- **Emulator screen model.** `screen/models.py:ilm`, the model behind the +0.066 screen,
  gives the same table.
- **Signed metrics, exhaustive.** ER 0.879, MED 113.7, MRED 2.82 %, bias 0.000, max |E| 1024.
  Weighted by the chip's operands: MRED 2.33 %, bias +0.03.
- **Thesis Table 5.4** (unsigned 8-bit, uniform inputs, 10^6 samples), with
  `python3 -m src_int8.approx.ref.ilm`:

  | Metric | Ours | Paper |
  |---|---:|---:|
  | AE = mean(exact - approx) | 0.246 | 0.25 |
  | MRED | 0.0286 | 0.0275 |
  | NMED | 0.0070 | 0.0068 |

  MRED and NMED are 3-4 % above the paper. Our Mitchell model is off from the same table by a
  similar amount (MRED 0.0379 vs 0.0372, NMED 0.0093 vs 0.0091), which points to a difference
  in the paper's sampling or normalisation, not in the ILM logic. Table 5.4 only matches
  without the 2^7 up-rounding cap: with the cap, inputs of 192 or more give MRED 0.056. So the
  table was evaluated with a 9-bit NOD, and the cap only matters for its hardware.

## 2. Method (identical for every variant)

### DC synthesis (`syn/run_dc.csh`, `syn/sweep_all.sh`)

- Combinational `mq_mul8` on its own.
- Inputs are driven by the chip's input driver cell; outputs are loaded with 4 x the
  reference load pin.
- Wire-load model, `compile_ultra` with DesignWare allowed for every variant, and
  `set_max_delay` from inputs to outputs.
- The target sweep is 0.3, 0.5, 0.7, 0.9, 1.2, 1.5, 2.0, 3.0 and 4.0 ns, at tt and at ss. The
  0.3 ns target is below what any design can reach, so it gives each design's minimum delay.
- The 4 ns target is the chip's pipeline stage: the point the multiplier would actually be
  built at.

### Power (`syn/run_power.csh`, `syn/power_all.sh`)

- tt corner, one operation per 4 ns (the chip's 250 MHz clock), 65,536 operations per run.
- VCS gate-level simulation with the DC SDF back-annotated, so glitches are counted. The SAIF
  annotated 100 % of nets in every run, and goes into PrimePower in averaged mode.
- Two vector sets: `chip` (65,536 consecutive `mq_mul8` input changes from the chip TB, i.e.
  real weight x activation pairs) and `random` (uniform).
- `zd` runs repeat the chip vectors with a zero-delay simulation (no glitches) to separate
  glitch power.
- Every run's output checksum equals the variant's Python/RTL product table (36 SDF runs and
  6 zero-delay runs).

### Metrics

- PDP = power (chip vectors) x achieved critical delay.
- Energy per operation = power x 4 ns.
- Changes are against `exact`.

## 3. Results

### Operating point: 4 ns target, tt

| Variant | Area um2 | Delay ns | P chip uW | P random uW | E/op pJ | PDP fJ | Area | P chip | P random | PDP | P chip, zero-delay uW (change) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| exact (`a*b`) | 481 | 1.58 | 163.5 | 173.0 | 0.654 | 258 | | | | | 108.4 |
| exact_dadda | 588 | 1.27 | 142.7 | 151.6 | 0.571 | 182 | +22.2 % | -12.7 % | -12.4 % | -29.5 % | 112.2 (+3.5 %) |
| C-SSM m=5 | 293 | 1.51 | 113.2 | 101.7 | 0.453 | 171 | **-39.0 %** | **-30.8 %** | -41.2 % | **-33.7 %** | 68.7 (-36.7 %) |
| C-SSM m=6 | 385 | 1.90 | 216.9 | 205.8 | 0.868 | 412 | -20.0 % | +32.6 % | +18.9 % | +59.9 % | 95.7 (-11.8 %) |
| C-SSM m=7 | 531 | 1.68 | 194.5 | 245.6 | 0.778 | 326 | +10.4 % | +18.9 % | +42.0 % | +26.8 % | 116.7 (+7.6 %) |
| ILM | 724 | 2.83 | 352.9 | 293.7 | 1.412 | 999 | +50.5 % | +115.8 % | +69.8 % | +288 % | 136.1 (+25.5 %) |

Every design meets 4 ns at ss as well: the worst is the ILM at 3.89 ns, and the others need
3.3 ns or less.

### Iso-delay mid point: 1.2 ns target, tt (all designs at 1.19-1.20 ns)

| Variant | Area um2 | P chip uW | Area | P chip | P random | PDP |
|---|---:|---:|---:|---:|---:|---:|
| exact | 541 | 160.3 | | | | |
| exact_dadda | 588 | 143.4 | +8.7 % | -10.6 % | -6.6 % | -9.7 % |
| C-SSM m=5 | 294 | 116.8 | -45.7 % | -27.1 % | -38.1 % | -27.1 % |
| C-SSM m=6 | 437 | 186.8 | -19.2 % | +16.5 % | +9.0 % | +17.3 % |
| C-SSM m=7 | 555 | 187.9 | +2.7 % | +17.2 % | +33.8 % | +18.0 % |
| ILM | 1,521 | 583.0 | +181 % | +264 % | +200 % | +268 % |

### Minimum delay (0.3 ns target)

| Variant | tt delay ns | tt area um2 | tt P chip uW (vs exact) | ss delay ns |
|---|---:|---:|---:|---:|
| exact | 0.56 | 1,027 | 272.6 | 0.90 |
| exact_dadda | 0.54 | 1,161 | 253.7 (-6.9 %) | 0.85 |
| C-SSM m=5 | 0.58 | 896 | 266.0 (-2.4 %) | 0.87 |
| C-SSM m=6 | 0.62 | 1,075 | 373.3 (+36.9 %) | 0.96 |
| C-SSM m=7 | 0.67 | 1,463 | 517.8 (+89.9 %) | 1.03 |
| ILM | 0.87 | 3,542 | 1,051 (+286 %) | 1.32 |

The full area-delay curves for both corners are in `results/hw_tables.md`. Above about 1.5 ns
(tt) every design is at its minimum area. Below 0.9 ns, area roughly doubles. DC results
along the sweep are not strictly monotonic: they vary by up to about 15 % between
neighbouring targets.

## 4. Comparison with the papers

### C-SSM (TCAS-I 2022, Fig. 10, signed, 28 nm)

The paper's power changes are about -64 / -41 / -4 % for m = 4 / 5 / 6. Our trend in m is the
same, but the curve sits higher.

- **Glitch-free power.** Without glitches (zero-delay activity), our m = 5 / 6 give -37 /
  -12 % against `a*b`, and -39 / -15 % against the structural Dadda baseline. That is close to
  the paper.
- **Glitch power.** With the SDF-timed activity, glitches take most of the saving, for two
  reasons:
  - The segment-detect logic is slow, and it drives both the operand muxes and the output
    shifter. The inner multiplier therefore evaluates twice per operation.
  - The C-SSM's power is 1.6-2.3 x its zero-delay value. For `exact` the ratio is 1.5 x.
- **Effect per m.** m = 6 goes from -12 % to +33 %. m = 5 stays at -31 %, because its inner
  multiplier is small.
- **Chip vs random vectors.** The chip's activations are small, and C-SSM is exact on small
  operands, so its saving on the chip vectors is smaller than on random ones (m = 5: -31 % vs
  -41 %).
- **Baseline.** The paper's exact reference is a structural multiplier. DC's `a*b` with
  DesignWare is a stronger baseline: 18 % less area than our structural Dadda tree at 4 ns,
  though 15 % more power.
- **Area.** The area trend matches the open-source proxy in `approx_cssm.md` (-36 / -20 /
  +9 %), here -39 / -20 / +10 %.

### ILM (thesis Table 5.6, 28 nm, unsigned)

The paper reports ILM-0 at 287 um2, 53.7 uW and 1.68 ns. It compares only against other
logarithmic multipliers (ILM-0 vs Mitchell: +2 % area, -19 % power) and gives no
exact-multiplier baseline.

At 8 bits our ILM is larger and hungrier than an optimised exact multiplier: +50 % area and
+116 % power at 4 ns. Reasons:

- Logarithmic multipliers scale linearly with the bit width and array multipliers
  quadratically (the thesis says so itself). At n = 8 the two NODs, two variable shifters,
  the decoder and the three-operand 18-bit adder cost as much as an 8 x 8 tree.
- The signed version adds two input negators and an output conditional negation.
- We use generic adders, not the thesis' one-hot "proposed FA" (Table 5.2/5.3: -33 % area per
  full adder). That only affects the final 16-bit adder, which is a small part of the +243 um2
  gap.
- The deep NOD -> shifter -> adder path makes the ILM the slowest design: 0.87 ns minimum
  delay against 0.56 ns for exact.

## 5. Recommendation (4 ns operating point)

| Variant | dBPB | Area | Power (chip) | Verdict |
|---|---:|---:|---:|---|
| C-SSM m=5 | +0.78 | -39 % | -31 % | the only real saving, but the LM cost is about 10 x the next one: reject for this LM |
| C-SSM m=6 | +0.072 | -20 % | +33 % (zero-delay -12 %) | area-only win; power worse because of glitches |
| C-SSM m=7 | +0.010 | +10 % | +19 % | no saving |
| ILM | +0.066 | +50 % | +116 % | no saving at 8 bits |
| exact_dadda | 0 | +22 % | -13 % | no LM cost; lower power than `a*b` |

- **No reproduced approximate design** saves power at an LM cost below +0.1 BPB at the
  chip's 4 ns point with realistic activity.
- **Power target.** Keep an exact multiplier. Structurally, the Dadda tree gives -13 % power
  (and -29 % PDP) at +22 % area with no accuracy loss. That is a cheaper win than any
  approximation here.
- **Area target.** C-SSM m = 6 is the best accuracy/area trade: -20 % area for +0.072 BPB.
  Phase C should benchmark m = 6, with m = 7 as the near-lossless control (+0.010 BPB, no
  hardware gain).
- **Headroom, not pursued.** C-SSM's glitch loss is structural. Balancing the select path, or
  moving segment detection into the operand's pipeline register stage, bounds m = 6 at about
  -12 % power (the zero-delay figure). ILM with the thesis' one-hot adder would shrink a little
  but stays above exact at 8 bits.

## 6. Commands

```
# server clone (code via git; vectors up with syn/sync.sh vec):
src_int8/approx/syn/sweep_all.sh tt "0.3 0.5 0.7 0.9 1.2 1.5 2.0 3.0 4.0"     # all of syn/variants.txt
src_int8/approx/syn/sweep_dc.sh <variant> <corner> "<delays>" [NAME=VALUE]     # one design
src_int8/approx/syn/power_all.sh tt 4.0 "chip random" 4 [list] [sdf|zd]
src_int8/approx/syn/run_power.csh <syn_tag> chip|random 4 [sdf|zd]           # one netlist
# local:
src_int8/approx/syn/sync.sh pull && python3 src_int8/approx/syn/collect.py --delay 4.0 --delay 1.2 --delay 0.3
python3 -m src_int8.approx.act.vectors --checksum <table.npy> build/approx/act/vec_chip.hex  # expected GLS checksum
python3 -m src_int8.approx.err.run ilm --ref ilm      # ILM exhaustive check;  python3 -m src_int8.approx.ref.ilm
```

DC logs show one benign `PROC-3` message per run (it cannot connect to a child process); there
are no other errors.
