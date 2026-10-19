# gan65_chip on 65 nm: results

`gan65_chip` is the INT8 Fashion-MNIST GAN generator accelerator (64-256-256-784, 16 PEs,
8 x 256x8 latch register files) on a 65 nm standard-cell library, pre-layout. Every number
below is taken from a summary in `results/` or a server log under `build/`. Method details
are in `docs/bench.md` (function) and `docs/synthesis.md` (flow, clock sweep).

Signoff: DC topographical at ss, **1.8 ns** netlist; PrimeTime at **2.0 ns = 500 MHz**
(ideal clocks, DC SPEF). The variant comparison is at **2.5 ns = 400 MHz** (2.4 ns
netlists), the fastest common clock the log-domain `mq:ilm` multiplier meets.

## 1. Function and bit-exactness

| Check | Result | Source |
|---|---|---|
| Golden integer model vs reference vectors | 8/8 seeds bit-exact | `python3 -m src_gan_tsmc65.golden.check_ref` |
| RTL (Verilator) vs golden, exact multiplier | 256/256 images bit-exact | `bench/results/exact_n256.md` |
| RTL vs integer emulation, every variant | 256/256 per variant | `docs/bench.md` |
| Real-data GAN metrics (FID-10k / IS / KID / P-R vs 60k train), RTL images | exact 78.65 FID (= int8 golden; float 77.76, real floor 1.49); ilm 79.17, trunc4 87.04, 1KR8 88.70, 1KVL 131.82, 1KR3 304.32 | `bench/results/real_n10000.md`, `docs/bench.md` |
| Formality RTL vs netlist | SUCCEEDED, 20,170 points, 0 failing (exact 1.8 ns) | `results/fm_exact_ss_p1.8.txt` |
| Formality, all other netlists | SUCCEEDED | `results/fm_*.txt` |
| Zero-delay GLS, exact, 2.0 ns, seed_0 | 784/784 pixels vs golden | `build/gls/exact_ss_p1.8_s0/tb.log` |
| SDF-timed GLS (tt), exact, 2.0 ns | 784/784 pixels vs golden | `build/gls/exact_ss_p1.8_s0_sdftt/tb.log` |
| SDF-timed GLS (tt), exact, 2.5 ns | 784/784 pixels vs golden | `build/gls/exact_ss_p2.4_s0_sdftt/tb.log` |
| GLS of trunc4 (2.0 and 2.5 ns), mq:ilm and the four mq:evo_* (2.5 ns), zero-delay and SDF | 784/784 pixels vs the variant's emulation | `python3 -m src_gan_tsmc65.sim.gls.check_pix <variant> pix.memh` |

One image takes **2,346,721 clk** in RTL and GLS alike (`docs/bench.md`).

## 2. Timing (exact multiplier, 1.8 ns netlist, PT at 2.0 ns)

| Corner | Setup WNS to flops | Hold WNS | Latch borrow (max) | RF read slack | File |
|---|---|---|---|---|---|
| ss | +0.183 ns | +0.068 ns | 0.79 ns | +0.501 ns | `results/sta_exact_ss_p1.8_ss_max_at2.0.txt` |
| tt | +0.788 ns | +0.024 ns | 0.59 ns | +0.991 ns | `results/sta_exact_ss_p1.8_tt_max_at2.0.txt` |
| ff (min RC) | +1.057 ns | **-0.0012 ns (2 endpoints)** | 0.48 ns | +1.264 ns | `results/sta_exact_ss_p1.8_ff_min_at2.0.txt` |

- Critical path: A/B RF read register `q_r` -> `gan_mul8` -> PE accumulator. PT Fmax of
  this netlist is about 550 MHz (1.817 ns; `docs/synthesis.md` s.2).
- **ff hold (pre-layout item).** `u_seq/u_rq/q_reg_{1,5}` -> `u_seq/rq_res_reg_{1,5}` is a
  direct Q -> D connection and misses by 1.2 ps (TNS -0.002 ns). DC already reports the same
  residue (`build/syn/exact_ss_p1.8/rpt/violators.rpt`). Tried in phase 3: a hold-only
  incremental pass (`compile -incremental_mapping -only_hold_time`) is not supported in
  topographical mode (OPT-1406); phase 2 tried cost priority and a 30 ps compile margin.
  No further DC fix was applied. The 2.4 ns netlists close ff hold at 2.5 ns (+0.7 to
  +1.6 ps, section 5). After CTS the P&R hold fix covers it together with real skew.

## 3. Area (exact, ss, 1.8 ns netlist; `results/syn_exact_ss_p1.8.txt`)

| Block | Area (um^2) | Share |
|---|---|---|
| **Total** | **182,751.5** (126,911 NAND2-eq) | 100 % |
| PE array (16 PEs) | 22,261.0 | 12.2 % |
| 16 x `gan_mul8` (713.8 each) | 11,420.3 | 6.2 % |
| Latch RF (8 x 256x8, with word ICGs) | 141,720.8 | 77.5 % |
| Rest (host, CSR, sequencer, requant, tanh ROM, controller, C buffer) | 18,769.7 | 10.3 % |

## 4. Power and energy per image

**Method.** PrimePower in **averaged** mode on the DC netlist with DC SPEF, ideal clocks
(no clock tree), switching activity from a gate-level SAIF of one real Fashion-MNIST image
(`ref_vectors/seed_0`): window START to STATUS = 2,333,768 clk, i.e. the whole weight stream
and all three layers; only the 784-pixel read-back (<1 %) is outside. 100 % of nets and
cells are annotated from the SAIF. Two activity sources:
- **SDF-timed GLS** (tt SDF from PrimeTime, inertial cell and net delays, ideal root clock):
  glitch transitions are counted as toggles. This is the headline number. It is not
  PrimePower's time-based glitch analysis (no VCD), but the glitches are in the toggle counts.
- **Zero-delay GLS**: no real glitches. Used for the ss/ff corners.

Energy per image = average power x 2,346,721 clk x period.

**Headline: tt, 500 MHz, SDF-timed activity** (`results/pwr_exact_ss_p1.8_exact_ss_p1.8_s0_sdftt_tt.txt`)

| | Power (mW) | Dynamic (mW) | Leakage (mW) | Share |
|---|---|---|---|---|
| **Chip** | **11.18** | 10.37 | 0.814 | 100 % |
| PE array | 0.679 | 0.558 | 0.121 | 6.1 % |
| 16 x mul8 alone | 0.338 | 0.268 | 0.070 | 3.0 % |
| Latch RF | 9.33 | 8.73 | 0.598 | 83.4 % |
| Rest | 1.17 | 1.08 | 0.094 | 10.5 % |

- **Energy per image 52.5 uJ** (48.7 dynamic + 3.8 leakage); **213 images/s** (4.69 ms).
- Power group `clock_network` is 9.58 mW (85.7 %): the 2,048 RF word ICGs and their latches
  on the free-running clock. The datapath is small next to it.
- Not in the totals: the root clock net, driven by the `clk` port before CTS (PrimePower
  books net power to the driver). Its load is 3.97 pF at 1 toggle/ns, so
  0.5 C V^2 f = 1.98 mW at 1.0 V nominal, or +9.3 uJ/image (about +18 %). After CTS this
  becomes clock-tree power.
- Glitches: SDF vs zero-delay changes the chip total by +1.2 % (11.18 vs 11.05 mW,
  `..._s0_tt.txt`) and the PE array by +10 %. The multipliers alone show -1.6 %: the
  zero-delay SAIF also counts zero-width delta glitches, which inertial delays filter out.

**Corners, zero-delay activity, 500 MHz** (`results/pwr_exact_ss_p1.8_exact_ss_p1.8_s0_{ss,tt,ff}.txt`)

| Corner (RC) | Total (mW) | Dynamic | Leakage | PE array | mul8 | Latch RF | Energy/image (uJ) |
|---|---|---|---|---|---|---|---|
| ss (max) | 9.14 | 7.97 | 1.17 | 0.583 | 0.334 | 7.59 | 42.9 |
| tt (max) | 11.05 | 10.24 | 0.81 | 0.617 | 0.343 | 9.27 | 51.9 |
| ff (min) | 17.02 | 15.29 | 1.73 | 0.888 | 0.475 | 14.43 | 79.9 |

Each row uses that corner's own library voltage and temperature, so ss is the lowest
dynamic power and ff the highest.

## 5. Multiplier variants (student comparison)

All variants at the same clock: DC ss 2.4 ns, PT and power at **2.5 ns (400 MHz)**, tt,
SDF-timed activity of seed_0, energy per image at 170.5 images/s. Quality is from the
256-latent benchmark (`docs/bench.md`). The last two columns are delay, not slack, from the
1.8 ns-target netlists with PT ss at 2.0 ns: the chip's minimum period (2.0 ns minus the ss
setup WNS to flops) and the multiplier's own a/b -> p delay inside the chip (largest over the
16 `gan_mul8` instances, from the first to the last internal point of the worst paths through
its outputs; `mul8_a_to_p_delay` in the PT summary).

| Variant | Total area (um^2) | 16 x mul8 (um^2) | PE array (um^2) | Chip power (mW) | PE power (mW) | mul8 power (mW) | Energy/image (uJ) | PSNR (dB) | Label agreement | FID-10k | IS | KID x10^3 | Precision | Recall | PT ss setup / ff hold @2.5 | GLS vs emulation | Min period ss (ns) | mul8 a->p delay ss (ns) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| exact | 174,855.2 | 9,890.3 | 18,948.6 | 8.816 | 0.416 | 0.192 | 51.72 | inf (bit-exact) | 100 % | 78.65 | 3.90 | 64.85 | 0.649 | 0.007 | +0.085 / +0.0016 | 784/784 | 1.817 | 0.937 |
| example_trunc4 | 171,815.8 (**-1.7 %**) | 9,398.5 (-5.0 %) | 16,856.6 | 8.783 (**-0.4 %**) | 0.401 | 0.189 (-1.5 %) | 51.53 (**-0.4 %**) | 24.65 | 94.9 % | 87.04 | 3.81 | 75.50 | 0.657 | 0.005 | +0.080 / +0.0008 | 784/784 | 1.811 | 0.981 |
| mq:ilm | 211,561.2 (**+21.0 %**) | 42,914.5 (+334 %) | 55,339.6 | 10.229 (**+16.0 %**) | 1.769 | 1.347 (+603 %) | 60.01 (**+16.0 %**) | 33.10 | 97.7 % | 79.17 | 3.89 | 65.36 | 0.649 | 0.006 | +0.077 / +0.0007 | 784/784 | **2.345** | 1.615 |
| mq:evo_1KV8 | 179,215.2 (**+2.5 %**) | 13,407.8 (+35.6 %) | 22,901.8 | 8.893 (**+0.9 %**) | 0.468 | 0.209 (+9.3 %) | 52.18 (**+0.9 %**) | inf (bit-exact) | 100 % | 78.65 | 3.90 | 64.85 | 0.649 | 0.007 | +0.087 / +0.0003 | 784/784 | **2.065** | 1.412 |
| mq:evo_1KR8 | 176,084.6 (**+0.7 %**) | 11,270.2 (+14.0 %) | 20,007.4 | 8.803 (**-0.1 %**) | 0.382 | 0.161 (-15.9 %) | 51.65 (**-0.1 %**) | 21.42 | 87.5 % | 88.70 | 3.79 | 76.37 | 0.619 | 0.004 | +0.083 / +0.0009 | 784/784 | **2.005** | 1.317 |
| mq:evo_1KVL | 171,282.6 (**-2.0 %**) | 8,519.4 (-13.9 %) | 16,118.3 | 8.722 (**-1.1 %**) | 0.304 | 0.115 (-39.8 %) | 51.17 (**-1.1 %**) | 12.19 | 51.2 % | 131.82 | 3.35 | 111.77 | 0.265 | 0.002 | +0.082 / +0.0012 | 784/784 | 1.894 | 1.192 |
| mq:evo_1KR3 | 163,118.9 (**-6.7 %**) | 2,288.9 (-76.9 %) | 8,261.6 | 8.556 (**-3.0 %**) | 0.182 | 0.032 (-83.1 %) | 50.19 (**-3.0 %**) | 8.60 | 8.2 % | 304.32 | 1.04 | 347.52 | 0.002 | 0.000 | +0.083 / +0.0015 | 784/784 | 1.820 | 0.842 |
| bw_exact (structured exact) | 175,303.8 (**+0.3 %**) | 10,730.2 (+8.5 %) | 19,617.5 | 8.791 (**-0.3 %**) | 0.388 | 0.147 (-23.5 %) | 51.57 (**-0.3 %**) | inf (bit-exact) | 100 % | 78.65 | 3.90 | 64.85 | 0.649 | 0.007 | +0.081 / +0.0011 | 784/784 | 1.811 | 1.010 |
| bw_axfa6 | 175,064.4 (**+0.1 %**) | 10,177.9 (+2.9 %) | 19,272.6 | 8.781 (**-0.4 %**) | 0.379 | 0.139 (-27.4 %) | 51.52 (**-0.4 %**) | 21.56 | 92.2 % | 96.90 | 3.73 | 87.23 | 0.655 | 0.005 | +0.088 / **-0.0044** | 784/784 | 1.810 | 1.004 |
| booth_exact (structured exact) | 176,536.1 (**+1.0 %**) | 11,102.4 (+12.3 %) | 20,352.6 | 8.815 (**-0.0 %**) | 0.407 | 0.154 (-19.4 %) | 51.72 (**-0.0 %**) | inf (bit-exact) | 100 % | 78.65 | 3.90 | 64.85 | 0.649 | 0.007 | +0.083 / +0.0017 | 784/784 | 1.814 | 1.000 |
| booth_axfa5 | 176,062.7 (**+0.7 %**) | 10,886.4 (+10.1 %) | 20,184.8 | 8.793 (**-0.3 %**) | 0.397 | 0.148 (-22.6 %) | 51.59 (**-0.3 %**) | 32.31 | 98.0 % | 78.31 | 3.91 | 64.26 | 0.643 | 0.007 | +0.081 / +0.0015 | 784/784 | 1.813 | 0.985 |
| booth_trunc5 | 171,282.2 (**-2.0 %**) | 8,683.9 (-12.2 %) | 16,251.1 | 8.795 (**-0.2 %**) | 0.389 | 0.153 (-20.1 %) | 51.60 (**-0.2 %**) | 6.31 | 39.1 % | 183.14 | 3.46 | 179.40 | 0.033 | 0.000 | +0.084 / +0.0013 | 784/784 | 1.812 | 1.045 |
| booth_akc | 169,077.2 (**-3.3 %**) | 7,621.2 (-22.9 %) | 14,393.9 | 8.673 (**-1.6 %**) | 0.266 | 0.094 (-50.8 %) | 50.88 (**-1.6 %**) | 11.32 | 64.8 % | 133.62 | 3.29 | 118.82 | 0.422 | 0.004 | +0.086 / +0.0016 | 784/784 | 1.816 | 0.996 |
| dralm_t4 | 171,244.8 (**-2.1 %**) | 5,703.5 (-42.3 %) | 15,448.0 | 8.755 (**-0.7 %**) | 0.351 | 0.111 (-42.0 %) | 51.36 (**-0.7 %**) | 19.97 | 86.3 % | 79.59 | 4.04 | 61.23 | 0.578 | 0.008 | +0.087 / +0.0007 | 784/784 | 1.817 | 0.964 |
| dralm_t5 | 173,497.0 (**-0.8 %**) | 6,395.8 (-35.3 %) | 17,570.5 | 8.805 (**-0.1 %**) | 0.415 | 0.142 (-25.7 %) | 51.66 (**-0.1 %**) | 23.45 | 90.2 % | 77.12 | 3.98 | 60.92 | 0.618 | 0.008 | +0.082 / +0.0016 | 784/784 | 1.817 | 1.001 |
| dralm_t6 | 174,334.0 (**-0.3 %**) | 7,399.8 (-25.2 %) | 18,800.3 | 8.836 (**+0.2 %**) | 0.443 | 0.159 (-17.2 %) | 51.84 (**+0.2 %**) | 25.61 | 91.0 % | 75.59 | 3.96 | 60.37 | 0.637 | 0.008 | +0.080 / +0.0009 | 784/784 | 1.742 | 0.946 |
| dralm_t6e | 182,306.5 (**+4.3 %**) | 15,613.6 (+57.9 %) | 26,364.2 | 9.150 (**+3.8 %**) | 0.696 | 0.416 (+117.3 %) | 53.68 (**+3.8 %**) | 30.90 | 94.5 % | 79.04 | 3.92 | 64.70 | 0.645 | 0.007 | +0.080 / +0.0009 | 784/784 | **2.005** | 1.250 |
| cdm_51 | 180,527.0 (**+3.2 %**) | 14,834.2 (+50.0 %) | 24,343.2 | 8.975 (**+1.8 %**) | 0.559 | 0.292 (+52.5 %) | 52.66 (**+1.8 %**) | 30.32 | 94.9 % | 79.09 | 3.88 | 65.82 | 0.645 | 0.006 | +0.088 / **-0.0061** | 784/784 | 1.840 | 1.037 |
| cdm_73 | 179,000.3 (**+2.4 %**) | 13,105.1 (+32.5 %) | 22,731.1 | 8.950 (**+1.5 %**) | 0.525 | 0.255 (+33.4 %) | 52.51 (**+1.5 %**) | 23.96 | 87.5 % | 82.51 | 3.82 | 69.97 | 0.636 | 0.007 | +0.086 / **-0.0053** | 784/784 | 1.815 | 1.054 |
| cdm_95 | 177,823.1 (**+1.7 %**) | 12,285.4 (+24.2 %) | 21,689.6 | 8.911 (**+1.1 %**) | 0.506 | 0.239 (+24.7 %) | 52.28 (**+1.1 %**) | 20.44 | 80.1 % | 83.92 | 3.76 | 71.71 | 0.621 | 0.004 | +0.082 / +0.0012 | 784/784 | 1.815 | 1.016 |
| cdm_51b (ablation) | 174,445.9 (**-0.2 %**) | 9,469.4 (-4.3 %) | 18,527.4 | 8.783 (**-0.4 %**) | 0.368 | 0.131 (-31.8 %) | 51.53 (**-0.4 %**) | 18.81 | 87.9 % | 102.20 | 3.68 | 93.63 | 0.647 | 0.005 | +0.082 / +0.0008 | 784/784 | 1.813 | 0.998 |

FID-10k / IS / KID / precision / recall: 10,000 RTL images vs the Fashion-MNIST train set
(`bench/results/real_n10000.md`, `docs/bench.md`). bw_* and booth_* are the structured
Baugh-Wooley / radix-4 Booth multipliers of `approx/` (`docs/papers/venkatachalam_ko_2017.md`);
the *_exact rows are their bit-exact baselines with the same dot diagram. booth_trunc5 and
booth_akc are truncated Booth multipliers after Aizaz & Khare 2022
(`docs/papers/aizaz_khare_2022.md`); their exact twin is booth_exact dralm_* are the dynamic-range
approximate logarithmic multipliers of Yin et al. 2021 (`docs/papers/yin_2021_dralm.md`);
dralm_t6e uses exact sign units instead of the paper's one's-complement ones. They have no
structured exact twin. cdm_* are the carry-disregard multipliers of Amirafshar et al. 2023
(`docs/papers/amirafshar_2023_cdm.md`): CDM8_51 / 73 / 95 with a sign-magnitude extension
(the paper is unsigned); cdm_51b is CDM8_51 on the plain Baugh-Wooley array (ablation), whose
exact twin is bw_exact.

Files: `results/syn_<v>_ss_p2.4.txt`, `results/sta_<v>_ss_p2.4_{ss_max,ff_min}_at2.5.txt`,
`results/pwr_<v>_ss_p2.4_<v>_ss_p2.4_s0_sdftt_tt.txt` (`<v>` = exact, example_trunc4,
mq_ilm, mq_evo_1KV8, mq_evo_1KR8, mq_evo_1KVL, mq_evo_1KR3, bw_exact, bw_axfa6, booth_exact,
booth_axfa5, booth_trunc5, booth_akc, dralm_t4, dralm_t5, dralm_t6, dralm_t6e, cdm_51, cdm_73, cdm_95, cdm_51b); zero-delay runs are the same names without `_sdftt` (exact 8.741, trunc4 8.709,
mq:ilm 9.626, evo_1KV8 8.759, evo_1KR8 8.691, evo_1KVL 8.614, evo_1KR3 8.501, bw_exact 8.675,
bw_axfa6 8.662, booth_exact 8.699, booth_axfa5 8.684, booth_trunc5 8.665, booth_akc 8.588, dralm_t4 8.658, dralm_t5 8.692,
dralm_t6 8.718, dralm_t6e 8.938, cdm_51 8.846, cdm_73 8.815, cdm_95 8.786, cdm_51b 8.661 mW).
Formality SUCCEEDED for all twenty-one
(`results/fm_*_ss_p2.4.txt`). GLS: zero-delay and SDF-timed pixels of seed_0 match each
variant's own integer emulation (`sim/gls/check_pix.py`); exact, evo_1KV8, bw_exact and
booth_exact also match the golden pixels. The four bw_* / booth_* variants run the whole
hardware flow with `syn/run_variant_flow.sh <v>` (also booth_trunc5, booth_akc, the dralm_* and the cdm_*). Delay columns: `results/sta_<v>_ss_p1.8_ss_max_at2.0.txt` (`setup_to_flops`,
`mul8_a_to_p_delay`), netlists `syn_<v>_ss_p1.8.txt`, FM `fm_<v>_ss_p1.8.txt` (all SUCCEEDED).

- All twenty-one meet ss setup at 400 MHz, and all but bw_axfa6, cdm_51 and cdm_73 meet ff hold.
  These miss ff hold by 4.4 / 6.1 / 5.3 ps on 7-8 endpoints, all `u_seq/u_rq/q_reg_*` ->
  `u_seq/rq_res_reg_*`: the direct Q -> D residue of section 2, outside the multiplier, left to
  the P&R hold fix like there.
- **Structured multipliers (bw_*, booth_*).** Written as gate-level Dadda trees, they are
  3-12 % larger than DC's `a * b` but use 19-27 % less multiplier power (SDF; zero delay:
  bw_exact 0.116 vs exact 0.187 mW, with lower leakage too), so they save 0.3-0.4 % chip energy
  even when exact. The approximate cells then save, against their own exact baseline:
  bw_axfa6 -5.1 % mul8 area, -5.1 % mul8 power, -0.1 % energy (FID 96.9, PSNR 21.6 dB);
  booth_axfa5 -1.9 % mul8 area, -4.1 % mul8 power, -0.2 % energy, -1.6 % mul8 delay
  (FID 78.3 vs 78.65 exact). Both beat DC's exact multiplier on chip power,
  energy, mul8 power and minimum period, but not on mul8 area or mul8 delay.
- **Truncated Booth (booth_trunc5, booth_akc).** Both are smaller and lower-power than both
  exact baselines; percentages vs exact / vs booth_exact. booth_akc (TACBM w = 6): mul8 area
  -22.9 / -31.4 %, mul8 power -50.8 / -39.0 % (zero delay 0.080 mW), chip power and energy
  -1.6 / -1.6 %, mul8 delay +6.3 / -0.5 %, minimum period -0.0 / +0.1 %. It is the largest chip
  energy saving of any variant with recognisable images, but FID 133.6 (64.8 % labels), about
  evo_1KVL, from a -43 bias per product at b >= 0. booth_trunc5: mul8 area -12.2 / -21.8 %,
  mul8 power -20.1 / -1.0 % (zero delay -7.1 % vs booth_exact), energy -0.2 / -0.2 %, minimum
  period -0.3 / -0.1 %, mul8 delay +11.6 / +4.5 %; its constant +32 also hits the zero products,
  so the images are unusable (FID 183, 6.3 dB). Fixed-zero product bits also shrink the
  accumulators (PE array -4,100 um^2 for booth_trunc5, -6,000 for booth_akc vs booth_exact).
- **500 MHz:** `mq:ilm` (-0.345 ns, 406 endpoints), `mq:evo_1KV8` (-0.065 ns, 183 endpoints),
  `mq:evo_1KR8` (-0.005 ns, 15 endpoints) and `dralm_t6e` (-0.005 ns, 16 endpoints) miss ss
  setup at 2.0 ns on their 1.8 ns-target netlists; all other variants meet it. The minimum period follows the
  multiplier delay once the multiplier is slower than about 1.0 ns. Below that the chip is
  limited by other paths: for exact and evo_1KR3 the worst flop path is the RF write enable
  `u_seq/dla_wr_en_reg` -> A-buffer `q_r` (through-mul8 minimum periods 1.816 and 1.812 ns).
- The multiplier delay depends on how hard DC sized it: trunc4 (0.981 ns) is a little slower
  than exact (0.937 ns) inside the chip because it had more slack at 1.8 ns, not because its
  logic is deeper.
- evo_1KV8 is bit-exact but 36 % larger and slower than the DC-built exact multiplier, so it
  only costs. evo_1KR3 saves the most (-6.7 % area, -3.0 % energy) but its images are
  unusable (8.6 dB, 8.2 % label agreement); evo_1KVL (-1.1 % energy) is also far below trunc4
  in quality.
- The exact and trunc4 multipliers are only 5-6 % of the area and 2 % of the power; the latch RF and its
  clock gating dominate. A cheaper multiplier therefore moves the chip totals little
  (trunc4: -0.4 % energy, for 24.65 dB PSNR and 94.9 % label agreement).
- `mq:ilm` gives better images than trunc4 but costs 4.3x the multiplier area and 7x its
  power with glitches (zero-delay: 5.1x). Timed activity matters for such deep logic: its
  multiplier power is 42 % higher with SDF than with zero delay.
- At 500 MHz (1.8 ns netlists) trunc4 vs exact: area -2.0 %, mul8 area -9.4 %, chip power
  -0.4 %, mul8 power -10.7 % (`results/pwr_example_trunc4_ss_p1.8_*_sdftt_tt.txt`).

- **Logarithmic DR-ALM (dralm_*).** Unlike `mq:ilm`, the paper's DR-ALMs are smaller and
  lower-power multipliers than DC's `a * b`: mul8 area -42 / -35 / -25 % and mul8 power
  -42 / -26 / -17 % for t = 4 / 5 / 6, at FID 79.6 / 77.1 / 75.6 (exact 78.65). The truncation
  keeps the shifters and the adder at t bits, and the one's-complement sign units cost one
  gate per bit. Chip energy follows only for t = 4 (-0.7 %) and t = 5 (-0.1 %); for t = 6 the
  PE accumulators burn more than the multiplier saves (PE power 0.443 vs 0.416 mW), so chip
  power is +0.2 %. dralm_t6 has the lowest minimum period of all variants (1.742 ns): its
  worst path runs through the multiplier and is 0.07 ns shorter than exact's, and the RF
  write-enable path that limits exact closed better in this netlist; its own mul8 delay is
  +1.0 %. dralm_t6e (same core, exact two's-complement sign units, not in the paper) beats
  exact on nothing: +58 % mul8 area, +117 % mul8 power, +3.8 % energy, 2.005 ns. Its two
  extra negation carry chains are in series with the log datapath; at a relaxed 4.0 ns its
  mul8 area is +9.6 % over exact's (8,752 vs 7,984 um^2, `results/syn_{exact,dralm_t6e}_ss_p4.txt`),
  so most of the cost is DC upsizing for 400 MHz. The same exact negations at both ends are part
  of `mq:ilm`'s cost. Despite their +27..+30 bias per product at b >= 0, the paper-sign
  DR-ALMs reach FIDs at or below exact (PSNR vs golden 20-26 dB); the error is a magnitude
  error of both signs, not the one-sided bias of the truncated Booth multipliers.
- **Carry-disregard multipliers (cdm_*).** The paper's CDM8s are unsigned. On this signed chip
  the carry disregard itself saves what the paper reports: cdm_51b (CDM8_51 on the Baugh-Wooley
  array) has -11.8 % mul8 area and -10.9 % mul8 power against its twin bw_exact (paper: -10.4 /
  -8.8 % vs its exact array) and beats exact on area (-0.2 %), mul8 area (-4.3 %), chip power and
  energy (-0.4 %); but every error of a two's-complement CDM is <= 0 (the dense bits of small
  negative weights lose carries), a -14 bias per product, and the images drop to 18.8 dB
  (FID 102.2). The sign-magnitude versions cdm_51 / 73 / 95 are unbiased and keep the paper's
  error per magnitude (FID 79.1 / 82.5 / 83.9, PSNR 30.3 / 24.0 / 20.4 dB), but beat exact on no
  hardware metric: mul8 area +50 / +33 / +24 %, mul8 power +53 / +33 / +25 %, energy +1.8 /
  +1.5 / +1.1 %, mul8 delay +9 to +13 % (their 1.815 ns minimum period vs exact's 1.817 is noise).
  The one's-complement magnitudes, the exact correction rows and the per-bit sign XORs cost
  about +50 % gates on the exact array, more than the carry disregard saves (9 / 25 / 43 % of
  the unsigned core), and not because of timing (cdm_73 at 4.0 ns: +33.7 % mul8 area vs exact,
  `results/syn_{exact,cdm_73}_ss_p4.txt`). At 8 bits the paper's savings do not survive an
  unbiased signed extension.

### 5.1 All variants at a glance

FID-10k / IS / KID / precision (P) / recall (R) from 10,000 RTL images; label agreement from
the 256-latent benchmark; hardware as in the table above (400 MHz, tt SDF power), minimum period
and mul8 delay from the 1.8 ns netlists. Percentages vs `exact` (DC's `a * b`). `mq:evo_1KV8`
is the EvoApprox library's own exact 8-bit multiplier (a bit-exact reference, 36 % larger than
DC's); `mq:ilm` is the counter-example of a published approximate multiplier that costs more
than exact on every hardware metric at 8 bits.

| Variant | FID-10k | IS | KID x10^3 | P | R | Labels (256) | Area (um^2) | 16 x mul8 (um^2) | Chip / mul8 power (mW) | Energy (uJ) | Min period (ns) | mul8 delay (ns) | % vs exact: area / mul8 area / chip power / mul8 power / energy / min period / mul8 delay |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| exact | 78.65 | 3.90 | 64.85 | 0.649 | 0.007 | 100.0 % | 174,855.2 | 9,890.3 | 8.816 / 0.192 | 51.72 | 1.817 | 0.937 | +0.0 / +0.0 / +0.0 / +0.0 / +0.0 / +0.0 / +0.0 |
| mq:evo_1KV8 (library exact) | 78.65 | 3.90 | 64.85 | 0.649 | 0.007 | 100.0 % | 179,215.2 | 13,407.8 | 8.893 / 0.209 | 52.18 | 2.065 | 1.412 | +2.5 / +35.6 / +0.9 / +9.3 / +0.9 / +13.6 / +50.8 |
| mq:evo_1KR8 | 88.70 | 3.79 | 76.37 | 0.619 | 0.004 | 87.5 % | 176,084.6 | 11,270.2 | 8.803 / 0.161 | 51.65 | 2.005 | 1.317 | +0.7 / +14.0 / -0.1 / -15.9 / -0.1 / +10.3 / +40.5 |
| mq:evo_1KVL | 131.82 | 3.35 | 111.77 | 0.265 | 0.002 | 51.2 % | 171,282.6 | 8,519.4 | 8.722 / 0.115 | 51.17 | 1.894 | 1.192 | -2.0 / -13.9 / -1.1 / -39.8 / -1.1 / +4.2 / +27.3 |
| mq:evo_1KR3 | 304.32 | 1.04 | 347.52 | 0.002 | 0.000 | 8.2 % | 163,118.9 | 2,288.9 | 8.556 / 0.032 | 50.19 | 1.820 | 0.842 | -6.7 / -76.9 / -3.0 / -83.1 / -3.0 / +0.2 / -10.1 |
| mq:ilm (counter-example) | 79.17 | 3.89 | 65.36 | 0.649 | 0.006 | 97.7 % | 211,561.2 | 42,914.5 | 10.229 / 1.347 | 60.01 | 2.345 | 1.615 | +21.0 / +333.9 / +16.0 / +603.3 / +16.0 / +29.1 / +72.4 |
| example_trunc4 | 87.04 | 3.81 | 75.50 | 0.657 | 0.005 | 94.9 % | 171,815.8 | 9,398.5 | 8.783 / 0.189 | 51.53 | 1.811 | 0.981 | -1.7 / -5.0 / -0.4 / -1.5 / -0.4 / -0.3 / +4.7 |
| bw_exact | 78.65 | 3.90 | 64.85 | 0.649 | 0.007 | 100.0 % | 175,303.8 | 10,730.2 | 8.791 / 0.147 | 51.57 | 1.811 | 1.010 | +0.3 / +8.5 / -0.3 / -23.5 / -0.3 / -0.3 / +7.8 |
| bw_axfa6 | 96.90 | 3.73 | 87.23 | 0.655 | 0.005 | 92.2 % | 175,064.4 | 10,177.9 | 8.781 / 0.139 | 51.52 | 1.810 | 1.004 | +0.1 / +2.9 / -0.4 / -27.4 / -0.4 / -0.4 / +7.1 |
| booth_exact | 78.65 | 3.90 | 64.85 | 0.649 | 0.007 | 100.0 % | 176,536.1 | 11,102.4 | 8.815 / 0.154 | 51.72 | 1.814 | 1.000 | +1.0 / +12.3 / -0.0 / -19.4 / -0.0 / -0.1 / +6.8 |
| booth_axfa5 | 78.31 | 3.91 | 64.26 | 0.643 | 0.007 | 98.0 % | 176,062.7 | 10,886.4 | 8.793 / 0.148 | 51.59 | 1.813 | 0.985 | +0.7 / +10.1 / -0.3 / -22.6 / -0.3 / -0.2 / +5.1 |
| booth_trunc5 | 183.14 | 3.46 | 179.40 | 0.033 | 0.000 | 39.1 % | 171,282.2 | 8,683.9 | 8.795 / 0.153 | 51.60 | 1.812 | 1.045 | -2.0 / -12.2 / -0.2 / -20.1 / -0.2 / -0.3 / +11.6 |
| booth_akc | 133.62 | 3.29 | 118.82 | 0.422 | 0.004 | 64.8 % | 169,077.2 | 7,621.2 | 8.673 / 0.094 | 50.88 | 1.816 | 0.996 | -3.3 / -22.9 / -1.6 / -50.8 / -1.6 / -0.0 / +6.3 |
| dralm_t4 | 79.59 | 4.04 | 61.23 | 0.578 | 0.008 | 86.3 % | 171,244.8 | 5,703.5 | 8.755 / 0.111 | 51.36 | 1.817 | 0.964 | -2.1 / -42.3 / -0.7 / -42.0 / -0.7 / +0.0 / +2.9 |
| dralm_t5 | 77.12 | 3.98 | 60.92 | 0.618 | 0.008 | 90.2 % | 173,497.0 | 6,395.8 | 8.805 / 0.142 | 51.66 | 1.817 | 1.001 | -0.8 / -35.3 / -0.1 / -25.7 / -0.1 / +0.0 / +6.8 |
| dralm_t6 | 75.59 | 3.96 | 60.37 | 0.637 | 0.008 | 91.0 % | 174,334.0 | 7,399.8 | 8.836 / 0.159 | 51.84 | 1.742 | 0.946 | -0.3 / -25.2 / +0.2 / -17.2 / +0.2 / -4.1 / +1.0 |
| dralm_t6e | 79.04 | 3.92 | 64.70 | 0.645 | 0.007 | 94.5 % | 182,306.5 | 15,613.6 | 9.150 / 0.416 | 53.68 | 2.005 | 1.250 | +4.3 / +57.9 / +3.8 / +117.3 / +3.8 / +10.4 / +33.5 |
| cdm_51 | 79.09 | 3.88 | 65.82 | 0.645 | 0.006 | 94.9 % | 180,527.0 | 14,834.2 | 8.975 / 0.292 | 52.66 | 1.840 | 1.037 | +3.2 / +50.0 / +1.8 / +52.5 / +1.8 / +1.3 / +10.7 |
| cdm_73 | 82.51 | 3.82 | 69.97 | 0.636 | 0.007 | 87.5 % | 179,000.3 | 13,105.1 | 8.950 / 0.255 | 52.51 | 1.815 | 1.054 | +2.4 / +32.5 / +1.5 / +33.4 / +1.5 / -0.1 / +12.5 |
| cdm_95 | 83.92 | 3.76 | 71.71 | 0.621 | 0.004 | 80.1 % | 177,823.1 | 12,285.4 | 8.911 / 0.239 | 52.28 | 1.815 | 1.016 | +1.7 / +24.2 / +1.1 / +24.7 / +1.1 / -0.1 / +8.5 |
| cdm_51b (ablation) | 102.20 | 3.68 | 93.63 | 0.647 | 0.005 | 87.9 % | 174,445.9 | 9,469.4 | 8.783 / 0.131 | 51.53 | 1.813 | 0.998 | -0.2 / -4.3 / -0.4 / -31.8 / -0.4 / -0.2 / +6.5 |

Paper sources: `docs/papers/venkatachalam_ko_2017.md` (bw_*, booth_axfa5),
`docs/papers/aizaz_khare_2022.md` (booth_trunc5, booth_akc), `docs/papers/yin_2021_dralm.md`
(dralm_*), `docs/papers/amirafshar_2023_cdm.md` (cdm_*; the sign-magnitude cdm_51 / 73 / 95 beat
exact on no hardware metric, see s.5). Best trade-offs so far: booth_axfa5 (FID 78.3, -0.3 % energy), dralm_t4 (FID 79.6,
-0.7 % energy, -42 % mul8 area) and booth_akc (largest energy saving with recognisable images,
-1.6 %, at FID 133.6).

## 6. How a student adds and evaluates a multiplier

1. Copy `bench/variants/example_trunc4.v` to `bench/variants/my_mul.v`; keep module
   `gan_mul8 (a, b, p)` (signed 8 x 8 -> 16, `a` = weight, `b` = activation).
2. Quality, locally: `bench/run_bench.sh my_mul` -> PSNR and label agreement over 256
   latents in `bench/results/my_mul_n256.md` (about 1 min).
3. Hardware, on the server clone after `git push` / `git pull`:
   - `syn/run_syn.sh my_mul --period 2.4 --signoff --sta-period 2.5` (DC, Formality, PT
     ss/tt/ff; about 10 min);
   - `power/run_power.sh my_mul --clock 2.5 --syn-period 2.4 --sdf` (SDF-timed GLS of one
     image + PrimePower tt; about 10 min). Without `--sdf` it uses zero-delay activity;
     `--corners "tt ss ff"` adds corners.
4. Check the netlist's function: copy `build/gls/my_mul_ss_p2.4_s0_sdftt/pix.memh` and run
   `python3 -m src_gan_tsmc65.sim.gls.check_pix my_mul pix.memh` (784/784 expected).
5. `sync.sh pull` copies the summaries to `results/`; compare with the table above.

## 7. Limits

- Pre-layout: no clock tree (root clock net estimated separately), DC estimated parasitics,
  ideal clocks. The ff hold residue of the 1.8 ns netlist is left to the P&R hold fix.
- Power is averaged over one image (seed_0). The activity is set by the weight stream and
  the RF clock gating, so other latents should give similar numbers; this was not measured.
- Leakage and dynamic power depend on the library corner; energy/image uses tt.
