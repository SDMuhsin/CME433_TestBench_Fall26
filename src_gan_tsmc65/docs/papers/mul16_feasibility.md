# 16-bit feasibility: do the CDM and HAM 16-bit claims hold in this 65 nm flow?

Question: before building a 16-bit GAN accelerator, do the 16-bit hardware gains of Amirafshar
et al. 2023 (carry-disregard multipliers, CDM16, `amirafshar_2023_cdm.md`) and Shi et al. 2025
(hybrid log / PWL multipliers, HAM H9C1, `shi_2025_ham.md`) appear in the gan65 flow? Yin et al.
2021 (DR-ALM, `yin_2021_dralm.md`) is included as the log-multiplier reference. Scope: the
multiplier block alone, between registers; no 16-bit chip.

## 1. Bench

- **Wrapper** `syn/mulbench/mul_bench.v`: input registers -> `mul_core` (N x N -> 2N) -> output
  register, so a -> p is register to register. One width parameter N (macro `MUL_N`, 8 or 16);
  every script takes the width, so the same flow runs mul8 and mul16 (and a later chip build can
  reuse the parameterisation; the chip RTL is untouched).
- **Designs** `approx/mulbench.py` (`designs(N)`), RTL generated into `syn/mulbench/rtl/w<N>/`.
  The generators were extended to 16 bits without changing a byte of the 8-bit chip variants
  (`approx/gen.py` regenerates `bench/variants/*.v` identically):
  `dralm_v.py` (any width, unsigned core), `ham_v.py` (HnC1 carry, BCT, -SP / -SO segment
  outputs, any width), new `cdm16_v.py` (four CDM8 netlists + CLAx without carry out;
  sign-magnitude wrapper), `cdm.signed16`.

| Design (N = 16) | What |
|---|---|
| `u_exact` / `s_exact` | `a * b` unsigned / signed (DesignWare, as the chip's `exact`) |
| `u_dadda` | exact unsigned AND array + Dadda tree + one CPA: structured exact twin of the CDMs |
| `u_cdm0000`, `u_cdmf880`, `u_cdmfbb3` | CDM16_wxyz, paper-native unsigned; 0000 = four exact 8-bit multipliers + the carry-dropping CLAx (the paper's structure with no carry disregard), f880 / fbb3 the paper's lowest-delay / best-PADEP designs |
| `u_dralm5`, `u_dralm6` | unsigned DR-ALM-5 / -6 (Yin Table 6) |
| `s_h9c1` | H9C1: PACC + SC + BCT (paper; = the chip `ham_a` sign scheme) |
| `s_h9c1sp`, `s_h9c1so` | H9C1-SP / -SO: OC magnitudes, segment outputs (paper, Table IV's best) |
| `s_h9c1e` | H9C1 with exact magnitudes (ablation, = chip `ham_ae` scheme) |
| `s_cdmf880`, `s_cdmfbb3` | signed CDM16, sign-magnitude (= chip `cdm_*` scheme: one's-complement magnitudes, exact correction terms, exact sign) |
| `s_dralm5`, `s_dralm6` | signed DR-ALM, paper sign units (= chip `dralm_t*`) |

HAM is natively signed in the paper (Table IV), so it is compared with the signed exact.
H6L9 is left out (its paper metrics are not reproduced, `shi_2025_ham.md` s.3).

## 2. RTL check and error metrics (`approx/results/mulbench_w16_error.md`)

`python3 -m src_gan_tsmc65.approx.mulbench_check --width 16`: 1,000,000 uniform random pairs +
4,096 corner pairs (zero, +-1, powers of two +-1, extremes, patterns). **Every design's RTL equals
its Python model on all 1,004,096 vectors**; N = 8 is checked exhaustively (65,536 pairs).

| Design | MRED (non-zero) | NMED | Reproduction it should match |
|---|---|---|---|
| u_cdm0000 / f880 / fbb3 | 1.98 / 2.03 / 2.30 % | 1.918 / 1.919 / 2.008e-3 | Table V exhaustive: NMED 1.914 / 1.915 / 2.000e-3, our MRED 1.97 / 2.02 / 2.29 % (paper prints half, s.3 of the CDM note) |
| u_dralm5 / 6 | 3.80 / 3.03 % (MRED_all) | 9.23 / 7.30e-3 | Table 2: 3.81 / 3.03 %, 9.23 / 7.30e-3 |
| s_h9c1 / sp / so / e (step-8 grid) | 0.786 / 0.723 / 0.734 / 0.689 % | 1.630 / 1.625 / 1.625 / 1.645e-3 | Table III reproduction: 0.786 / 0.721 / 0.735 %, 1.632 / 1.627 / 1.627e-3 |
| s_cdmf880 / fbb3 | 3.10 / 3.81 % | 3.78 / 4.15e-3 (/2^30) | no paper number (our signed extension) |
| s_dralm5 / 6 | 3.80 / 3.03 % | 9.22 / 7.31e-3 (/2^30) | Table 6 signed not reproduced (yin note) |

All match the earlier 16-bit reproductions to sampling noise.

## 3. Flow

Server, same library, corners and settings as the chip flow (`syn/scripts/dc_syn.tcl`): DC
topographical at ss, ff min library, `mq65.sdc` (IO delay 20 %, 0.25 ns setup uncertainty),
`compile_ultra -no_autoungroup -gate_clock` + incremental, `mul_core` hierarchy kept with no
boundary optimisation. Points: **2.5 ns** (400 MHz: area, Formality, power), **4.0 ns** (relaxed
area) and a **tight 1.2 ns** run (N = 8: 1.0 ns) for the fastest netlist: a -> p delay inside
`mul_core` and min period = period - WNS of the register path (includes clock-to-q, setup and
the 0.25 ns uncertainty). Formality RTL vs the 2.5 ns netlist: **SUCCEEDED for all 18 runs**.

Power: PrimePower tt averaged at 400 MHz, SAIF from an SDF-timed (tt) VCS GLS of 20,000
consecutive multiplies (one per clock), two stimulus sets (`syn/mulbench/stimulus.py`, seeded):
- **(a) uniform**: a, b uniform over all 16-bit patterns.
- **(b) GAN-like**: a = weight = round(N(0, sigma)), sigma = 2^15 / 4 = 8,192 (clipped to the
  signed range; full scale = 4 sigma); b = activation >= 0: 0 with probability 0.65, else
  round(|N(0, sigma)|) clipped to 32,767 (ReLU outputs; measured 64.7 % zeros, non-zero mean
  6,563). Unsigned designs get |a| (same magnitudes).
The GLS products of all 36 runs equal the models (`approx/mulbench_gls.py`). Energy/op = power x
2.5 ns. All numbers are the `mul_core` cells only (registers excluded).

## 4. Results (`syn/mulbench/results/table_w16.md`)

Percentages vs the exact design of the same signedness (`u_exact` / `s_exact`). Paper column =
the paper's own 16-bit savings vs its own exact multiplier (area / power / delay).

| Design | mul area @2.5 ns (um^2) | @4.0 ns | a->p delay (tight) | min period | power (a) uniform | power (b) GAN-like | energy/op (a) / (b) | paper (area / power / delay) |
|---|---|---|---|---|---|---|---|---|
| `u_exact` | 2,391 | 2,258 | 1.095 ns | 1.511 ns | 0.971 mW | 0.812 mW | 2.43 / 2.03 pJ | - |
| `u_dadda` | +16.4 % | +9.5 % | +4.4 % | +4.0 % | -17.5 % | -63.1 % | 2.00 / 0.75 | - |
| `u_cdm0000` | +11.0 % | +10.2 % | +9.6 % | +6.7 % | -5.7 % | -56.8 % | 2.29 / 0.88 | -2.2 / -4.3 / -23.7 % |
| `u_cdmf880` | **-17.8 %** | **-16.5 %** | **-10.6 %** | **-7.5 %** | **-39.0 %** | -74.6 % | 1.48 / 0.52 | -26.5 / -27.2 / -43.0 % |
| `u_cdmfbb3` | **-27.3 %** | **-24.5 %** | **-16.7 %** | **-13.0 %** | **-47.0 %** | -77.1 % | 1.29 / 0.47 | -32.8 / -33.2 / -43.0 % |
| `u_dralm5` | -75.4 % | -76.4 % | -23.3 % | -16.0 % | -84.2 % | -77.8 % | 0.38 / 0.45 | -67.1 / -87.9 / -47.0 % |
| `u_dralm6` | -72.2 % | -74.3 % | -22.7 % | -15.7 % | -81.4 % | -75.7 % | 0.45 / 0.49 | -60.7 / -85.0 / -47.0 % |
| `s_exact` | 2,132 | 1,892 | 1.056 ns | 1.472 ns | 0.880 mW | 0.788 mW | 2.20 / 1.97 pJ | - |
| `s_h9c1` | +37.9 % | **-10.8 %** | +74.3 % | +52.5 % | +95.2 % | +84.7 % | 4.30 / 3.64 | -48.6 / -55.8 / -23.4 % |
| `s_h9c1sp` | +47.1 % | **-12.1 %** | +75.2 % | +53.9 % | +101.6 % | +88.5 % | 4.43 / 3.71 | -50.6 / -57.5 / -23.4 % |
| `s_h9c1so` | +28.8 % | **-18.4 %** | +73.6 % | +51.3 % | +72.8 % | +58.9 % | 3.80 / 3.13 | -56.9 / -61.7 / -24.0 % |
| `s_h9c1e` | +77.2 % | -6.0 % | +87.4 % | +61.2 % | +170.4 % | +140.0 % | 5.95 / 4.73 | - |
| `s_cdmf880` | +60.7 % | +32.9 % | +37.1 % | +26.2 % | +51.3 % | -22.6 % | 3.33 / 1.52 | - |
| `s_cdmfbb3` | +56.2 % | +24.9 % | +35.3 % | +26.0 % | +67.0 % | -17.9 % | 3.67 / 1.62 | - |
| `s_dralm5` | -64.1 % | -65.8 % | +0.9 % | +0.4 % | -69.9 % | -67.0 % | 0.66 / 0.65 | -76.4 / -79.8 / +3.9 % |
| `s_dralm6` | -59.8 % | -62.6 % | +4.9 % | +3.8 % | -64.4 % | -63.2 % | 0.78 / 0.72 | -75.2 / -76.5 / -2.0 % |

Baselines differ: the CDM paper's Exact16 is four exact 8-bit arrays (1,348 um^2, 1.35 ns at
45 nm), the HAM paper's an exact radix-4 Booth multiplier (2,563 um^2, 1.75 ns), Yin's an exact
16-bit array; ours is DesignWare at the same constraints, a much stronger exact.

### Reading

- **CDM16, paper-native (unsigned): yes, real gains.** f880 / fbb3 beat DesignWare on every
  metric at 400 MHz: area -18 / -27 %, uniform power and energy -39 / -47 %, delay -11 / -17 %,
  min period -7.5 / -13 %. Against the paper's own baseline structure (`u_cdm0000`: the same
  four-multiplier + CLAx composition with exact CDM8s), f880 / fbb3 are **-26.0 / -34.5 % area**
  (paper -26.5 / -32.8 %), -35 / -44 % uniform power (paper -27 / -33 %), -18 / -24 % delay
  (paper -43 %). The area claim reproduces almost exactly, power is better, delay is about half.
  Against the structured exact twin `u_dadda`: -29.5 / -37.6 % area, -26 / -36 % power.
- **The GAN-like power column is mostly the array, not the approximation.** With 65 % zero
  activations every AND-array design (u_dadda -63 %, u_cdm0000 -57 %) drops far more than
  DesignWare's exact (-16 % from (a) to (b)); the carry disregard adds -31 / -38 % on top of
  `u_dadda`. A fair GAN-like comparison is against an array exact.
- **CDM16, signed (the sign scheme a GAN chip needs): no.** One's-complement magnitudes,
  correction terms and the exact output negation cost more than the carry disregard saves:
  +56 to +61 % area, +26 % min period, +51 to +67 % uniform power. Its only better number,
  GAN-like power -18 to -23 %, is the AND-array zero-activation effect above (the 8-bit
  `cdm_*` variants failed for the same reason).
- **HAM H9C1 family: no at 400 MHz.** Every 2.5 ns metric is worse (+29 to +77 % area, +59 to
  +170 % power), and the HAM is slower, not faster: 1.83-1.98 ns vs 1.06 ns (paper: -23 %).
  The serial LOD -> mantissa shift -> PWL adder -> 31-bit shifter path needs ~2.2 ns of the
  2.5 ns budget, so DC upsizes it. With timing relaxed (4.0 ns) the HAM is smaller than exact,
  -11 / -12 / -18 % for H9C1 / -SP / -SO, a quarter to a third of the paper's -49 to -57 %. So
  the HAM's area idea exists at 16 bits (at 8 bits it was +59 to +68 % even at 4.0 ns), but only
  with a relaxed clock (4.0 ns = 250 MHz; the crossover between 2.5 and 4.0 ns was not swept)
  and far below the paper's size.
- **DR-ALM (reference): the papers' claims hold** (area -60 to -76 %, power -64 to -84 %,
  unsigned delay -23 %, signed delay = exact), as at 8 bits.

## 5. Verdict

| Paper | >= 1 positive hardware metric at 16 bits here? | Big enough for a 16-bit chip to show it? |
|---|---|---|
| Amirafshar 2023 (CDM16) | **Yes, unsigned** (paper-native): area -18 / -27 %, power -39 / -47 %, delay -11 / -17 % vs DesignWare; area matches the paper vs its own baseline. **Signed (chip scheme): only GAN-like power** (-18 / -23 %), an array effect | Unsigned form: mul area -18 / -27 % ~ **-2 to -5 % chip area**, < 1-2 % chip power (below). Signed form: chip gets **larger** (+7 to +12 %). Only worth it if the datapath can stay unsigned (sign handled outside, e.g. sign-magnitude weights with the sign applied in the accumulator) |
| Shi 2025 (HAM H9C1) | **Only at a relaxed clock**: area -11 to -18 % at 4.0 ns; at 400 MHz none (area +29 to +77 %, power x1.7-2.7, delay +74 %) | **No** at 400 MHz (the chip would get +4 to +9 % larger and slower); at <= 250 MHz the -11 to -18 % mul area is ~-1.5 to -3.5 % of chip area |

Both papers' 16-bit savings are measured against weak exact baselines (array / hand Booth at
45 nm); against a synthesised DesignWare multiplier only the unsigned CDM keeps a clear,
paper-sized area gain. The DR-ALM remains the only design here with a chip-visible gain in its
signed form.

## 6. mul16 vs mul8 and the multiplier share of a 16-bit chip

| | exact mul8 | exact mul16 | ratio |
|---|---|---|---|
| this bench, signed, 2.5 ns | 497 um^2 | 2,132 um^2 | 4.29x |
| tight-period delay | 0.78 ns | 1.06 ns | 1.35x |
| power, uniform (GAN-like) | 0.228 (0.209) mW | 0.880 (0.788) mW | 3.9x (3.8x) |
| chip (16 instances, `results.md`) | 9,890 um^2 = 618 / instance | ~2,650 / instance (x4.29) | - |

The 8-bit chip is 174,855 um^2: latch RF 79.1 %, mul8 5.7 %, PE other 5.2 %, rest 10.1 %. A
16-bit chip with 16 multipliers: multipliers ~42,400 um^2. With the RF doubled for 16-bit
words (276,500) and PE accumulators / rest scaled x2 / x1: ~355,000 um^2 -> **multipliers
~12 % of the chip** (~20 % if the RF stays at today's bit count). In power the mul8 is 2.2 % of
the chip at 400 MHz; x3.9 for mul16 with a doubled RF gives **~4 %**. So a multiplier saving of
X % shows as ~0.12-0.20 X in chip area and ~0.04 X in chip power: CDM16 unsigned f880 / fbb3
~-2 to -5 % area, ~-1.5 to -2 % power; DR-ALM ~-7 to -15 % area, ~-3 % power.

## 7. 8-bit sanity check (same bench, N = 8; `syn/mulbench/results/table_w8.md`)

| Design | mul area @2.5 ns | a->p delay (1.0 ns run) | min period | power uniform / GAN-like |
|---|---|---|---|---|
| `s_exact` (N = 8) | 497 um^2 | 0.782 ns | 1.199 ns | 0.228 / 0.209 mW |
| `s_dralm5` (= chip dralm_t5) | 326 (-34.5 %) | 0.839 (+7.3 %) | 1.251 (+4.4 %) | 0.144 (-37.2 %) / 0.115 (-44.8 %) |

The chip's dralm_t5 row: mul8 area -35.3 %, mul8 delay +6.8 %, mul8 power -25.7 % (real image
activity), so the standalone bench reproduces the in-chip relations. The standalone exact mul8
(497 um^2) is 20 % smaller than the in-chip instance (618 um^2), where the RF read leaves less
of the cycle for the multiplier.

## 8. Reproduce

```
python3 -m src_gan_tsmc65.approx.mulbench --width 16          # RTL (also --width 8)
python3 -m src_gan_tsmc65.approx.mulbench_check --width 16    # RTL == model, metrics
src_gan_tsmc65/syn/mulbench/start.sh w16.log 16 3 <design> ...   # server: DC 2.5 / 4.0 / 1.2, FM, GLS + power
# copy build/summary/mb*_w16_* to syn/mulbench/results/, then
python3 -m src_gan_tsmc65.approx.mulbench_table --width 16
python3 -m src_gan_tsmc65.approx.mulbench_gls <dir with p.memh copies>
```
One design (`syn/mulbench/run_design.sh`) takes ~15 min at N = 16; 16 designs ran in ~1.5 h with
three in parallel. `syn/mulbench/clean.sh` removes the regenerable bulk (58 MB left).
