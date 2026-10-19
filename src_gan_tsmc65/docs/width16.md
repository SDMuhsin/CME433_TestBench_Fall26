# gan65_chip at 8 or 16 bits: the width-parameterised datapath

One configuration switch selects the datapath width of the GAN accelerator: **8** (the INT8
chip of `docs/results.md`, unchanged) or **16** (an INT16 chip for 16-bit approximate
multipliers). Everything else (64-256-256-784 G300 generator, 16 PEs, 4 x 4 tiling, host
protocol, CSR map, flow scripts) is shared.

## 1. How to toggle

The width is the include directory `rtl/cfg/w<W>/` (W = 8 | 16). It holds `gan65_cfg.vh`
(`` `define GAN65_DATA_W ``) and the matching CSR reset constants `g300_quant_params.vh`, so
the RTL and its requant shift can never disagree. Every script takes `--width`:

```bash
src_gan_tsmc65/bench/run_bench.sh exact --width 16                 # 256 latents, Verilator
src_gan_tsmc65/bench/run_bench.sh mb:park_14z --width 16 --n 16    # a 16-bit mul_core of syn/mulbench
src_gan_tsmc65/bench/run_real.sh --width 16                        # FID-10k etc. (rows *_w16)
src_gan_tsmc65/syn/run_syn.sh exact --width 16 --period 2.4 --signoff --sta-period 2.5   # server
src_gan_tsmc65/power/run_power.sh exact --width 16 --clock 2.5 --syn-period 2.4 --sdf    # server
python3 -m src_gan_tsmc65.golden.check_ref --width 16
python3 -m src_gan_tsmc65.quant.build --width 16                   # re-derive model/fmnist_w16
```

Default is 8 everywhere, with the historical output tags (`exact`, `exact_ss_p2.4`, ...);
width 16 appends `_w16` (`exact_w16_n256`, `exact_w16_ss_p2.4`). The DC run records the width
in `build/syn/<tag>/width`, which Formality, GLS and power read.

## 2. What changed in the RTL

| Block | 8-bit chip | Generalised |
|---|---|---|
| `pe/gan_mul.v` (new swap point) | `gan_mul8` | `gan_mul #(N) (a, b, p)`, signed N x N -> 2N, N = DATA_W |
| PE accumulator | 24 b | ACC_W = 2 DATA_W + 8 (24 / 40 b): 256-term sums of 2 DATA_W-bit products cannot overflow |
| A/B buffers | 8 x 256x8 latch RF | 8 x 256 x DATA_W (`dla_sram_1rw_256x8 #(W)`, name kept) |
| C buffer | 16 x 24 FF | 16 x ACC_W FF |
| `seq/e2e_seq.v` | 1 byte per element | `seq/e2e_word_asm.v` assembles DATA_W/8 little-endian bytes per element; stream = 283,984 elements (283,984 / 567,968 B), byte counter 19 / 20 b |
| `seq/e2e_requant.v` | 8 + 24 iterations, S = 16 | DATA_W + ACC_W iterations, shift S = `G300_REQ_SHIFT` (16 / 27), ReLU clamp 2^(DATA_W-1) - 1, registers sized from the parameters |
| tanh stage | 256-entry ROM, 8-bit pixel | unchanged: the Q20 pre-activation and the 8-bit output pixel do not depend on DATA_W; the pixel is sign-extended into the B word |
| host QSPI | byte protocol | unchanged |
| `host/e2e_dbg_pack.v` (new) | - | DBG_WR_A/B: byte address -> element address / NB, written on the last byte |
| CSRs | byte count 0x03-0x05 (19 b) | BC_W bits; C debug read 4 (8-bit) or 8 bytes per accumulator; M CSRs stay 32 b |
| pixel read-back | 1 byte per pixel | unchanged (low byte of the B word) |

Multiplier variants: `bench/variant.py --width W` resolves a variant to sources that define
`gan_mul`. A file may define `gan_mul` itself (any width) or a fixed-width module that
`bench/adapt/` wraps: `gan_mul8` (width 8, every existing `bench/variants/*.v`), `gan_mul16`
(width 16), `mq_mul8` (width 8), or `mul_core` of the standalone multiplier bench
(`mb:<design>` = `syn/mulbench/rtl/w<W>/<design>.v`). A width mismatch is an error. Emulation
for scoring: the exhaustive 256 x 256 table at 8 bits, the numpy model of `approx/mulbench.py`
for 16-bit `mb:` designs (`bench/mul_model.py`); other 16-bit variants report "n/a".

## 3. INT16 quantisation

`quant/ptq.py` re-derives the model from the float generator `model/fmnist/G300_float.npz`
with the scheme of the committed INT8 model (`quant/check.py` rebuilds `model/fmnist`
bit for bit from it), at Q = 2^(D-1) - 1:

- **Weights and biases:** per tensor, symmetric, s = r max|w| / Q, q = clamp(round(w / s), -Q, Q).
  INT8 uses clip ratios r = 0.9 / 0.65 / 0.4 on the three weight tensors; at 16 bits clipping
  only adds error, so every r = 1.0.
- **Latent:** sZ = p99.99(|z|) / Q over 512 calibration latents (torch seed 1000).
- **Hidden activations h0, h2:** static calibration, sH = p99.99(h) / Q of the float layer
  output computed from the previous layer's integer chip output. Both are ReLU outputs, so
  the codes are 0 .. Q and no zero point is needed.
- **Requant:** MA = round(sW sX / sY 2^S), MB = round(sb / sY 2^S) for the ReLU layers;
  MW4 / MB4 put the last layer on the Q20 grid of the tanh ROM (unchanged from INT8).
- **Shift S:** INT8 uses S = 16. For INT16 `quant/ptq.py` takes the largest S for which all
  six M fit the 32-bit CSRs: **S = 27** (`G300_REQ_SHIFT` in `rtl/cfg/w16/g300_quant_params.vh`).
  The smallest multiplier is MA0 = 2,140 (12 significant bits; INT8 MA0 = 243).

`model/fmnist_w16/` holds the result: weights/biases as 16-bit `G300_*.memh`, `csr.memh`, the
256 benchmark latents (same z as INT8, quantised with the INT16 sZ), 8 reference vectors and
`quant.json` (scales, CSRs, clip ratios, score vs float). `python3 -m src_gan_tsmc65.quant.build
--width 16` regenerates it.

## 4. Results (exact multiplier, 2026-10-19)

**Width 8 is unchanged.** With the width-parameterised RTL, `run_bench.sh exact --n 256` gives
44/44 pixel dumps byte-identical to the run before the change (2,346,721 clk/image);
`example_trunc4` and `mq:ilm` are identical too, with RTL == emulation 256/256. A fresh DC run
(ss, 2.4 ns) of the 8-bit exact chip gives 175,016.2 um^2 against the committed 174,855.2
(+0.09 %, DC run-to-run noise; mul8 9,907.9 vs 9,890.3), trunc4 171,997.2 vs 171,815.8, and
Formality SUCCEEDED on both (exact: 20,170 points, as committed;
`results/{syn,fm}_*_ss_p2.4_wchk.txt`).

**Function and quality of the INT16 chip**

| Check | INT16 chip | INT8 chip |
|---|---|---|
| Golden model vs reference vectors (`check_ref --width 16`) | 8/8 | 8/8 |
| RTL vs golden, 256 latents | 256/256 bit-exact | 256/256 |
| RTL vs golden, 10,000 latents | 10000/10000 bit-exact | 10000/10000 |
| Clock cycles per image | **4,606,025** (stream 567,968 B) | 2,346,721 (283,984 B) |
| PSNR / MAE vs the float generator, 256 latents | **46.79 dB** / 0.081 | 35.32 dB / 1.934 |
| PSNR / MAE vs float, 10,000 latents | 46.67 dB / 0.056 | - |
| Labels equal to the float generator's | 256/256; 9991/10000 | 250/256 |
| FID-10k / IS / KID x10^3 | **77.83** / 3.91 ± 0.06 / 63.90 ± 2.12 | 78.65 / 3.90 ± 0.07 / 64.85 ± 2.12 |
| Precision / Recall | 0.645 / 0.008 | 0.649 / 0.007 |
| CNN-FID / NN label agree | 30.81 / 71.7 % | 31.33 / 71.1 % |
| Zero-delay and SDF-timed GLS (tt), 2.5 ns, seed_0 | PASS, 784/784 pixels vs golden (both) | PASS |

The float generator scores FID 77.76, IS 3.91, KID 63.80, P 0.645, R 0.008, CNN-FID 30.79
(`bench/results/real_n10000.md`): the INT16 chip is within 0.07 FID of float, INT8 0.89. So
at 16 bits the quantisation error is essentially gone and a 16-bit approximate multiplier
is measured against an almost float-quality baseline.

**Hardware (DC topographical ss, 2.4 ns netlist; PT and power at 2.5 ns = 400 MHz;
`results/*exact_w16_ss_p2.4*`)**

| | INT16 chip | INT8 chip (`*exact_ss_p2.4*`) | Ratio |
|---|---|---|---|
| Total area (um^2) | **334,519.9** | 174,855.2 | 1.91x |
| PE array (16 PEs) | 54,835.2 (16.4 %) | 18,948.6 (10.8 %) | 2.89x |
| 16 x multiplier | **37,149.8 (11.1 %)**, 2,321.9 each | 9,890.3 (5.7 %), 618.1 each | 3.76x |
| Latch RF (8 x 256 x W) | 256,753.8 (76.8 %) | 138,249.0 (79.1 %) | 1.86x |
| Rest | 22,930.9 (6.9 %) | 17,657.6 (10.1 %) | 1.30x |
| Formality RTL vs netlist | SUCCEEDED, 37,341 points, 0 failing | SUCCEEDED | - |
| PT setup to flops ss / tt @2.5 | +0.083 / +0.927 ns | +0.085 / +0.936 ns | - |
| PT hold ss / tt / ff @2.5 | +0.063 / +0.021 / **-0.0043 ns (6 endpoints)** | ff +0.0016 | - |
| Multiplier a -> p delay in the chip, ss | 1.50 ns (2.4 ns netlist, relaxed sizing) | - | - |
| Chip power, tt, SDF activity | **10.24 mW** | 8.82 mW | 1.16x |
| PE array / multipliers / latch RF power | 0.967 (9.4 %) / **0.581 (5.7 %)** / 8.24 (80.5 %) mW | 0.416 (4.7 %) / 0.192 (2.2 %) / 7.47 (84.7 %) mW | 2.3x / 3.0x / 1.10x |
| Leakage | 1.47 mW | 0.72 mW | 2.0x |
| Energy per image | **117.97 uJ** (101.07 dyn + 16.89 leak) | 51.72 uJ | 2.28x |
| Images per second at 400 MHz | 86.8 | 170.5 | 0.51x |
| Chip / multiplier power, zero-delay activity | 10.10 / 0.590 mW, 116.35 uJ | 8.74 / 0.187 mW, 51.28 uJ | 1.16x |

- **Glitches.** SDF-timed vs zero-delay activity: chip +1.4 % (10.24 vs 10.10 mW), PE array
  +9 % (0.967 vs 0.887 mW), multipliers -1.4 % (zero-delay SAIF also counts zero-width delta
  glitches), the same pattern as at 8 bits (`docs/results.md` s.4).
- **Minimum period.** DC at 1.8 ns (`results/syn_exact_w16_ss_p1.8.txt`) does not close
  (-0.160 ns, 374,886.7 um^2, multipliers 64,423.4 = 17.2 %, 4,026.5 each); PT at 2.0 ns on
  that netlist gives setup to flops +0.025 ns, so the **minimum period is 1.975 ns ss
  (506 MHz)**, against 1.817 ns (550 MHz) for the INT8 chip with the same method. The critical
  path is the same (A/B RF read register -> multiplier -> 40-bit accumulator); the multiplier
  a -> p delay in that netlist is **1.200 ns** vs 0.937 ns at 8 bits (1.28x).
- **ff hold.** The 6 endpoints are `u_seq/u_rq/q_reg_*` -> `u_seq/rq_res_reg_*`, the same
  direct Q -> D pre-layout residue as the 8-bit 1.8 ns netlist (`docs/results.md` s.2); the
  P&R hold fix covers it.
- **Why energy grows 2.28x but power only 1.16x.** An image takes 1.96x the cycles (twice the
  weight bytes over the same 4-bit QSPI stream). The power is dominated by the RF word ICGs on
  the free-running clock (clock_network 78 % of the total); their count (2,048) does not
  change with the word width, so the RF power rises only 10 % while its area nearly doubles.
- **Multiplier share vs the prediction** of `docs/papers/mul16_feasibility.md` s.6 (chip
  ~355,000 um^2, multipliers ~12 % of the area, ~4 % of the power): measured 334,520 um^2,
  11.1 % of the area (2,322 um^2 per instance, 3.76x the in-chip mul8) and 5.7 % of the power
  (3.0x the mul8 power, while the chip power grows only 1.16x). A multiplier saving of X %
  therefore shows as about 0.11 X in chip area and 0.06 X in chip power at 400 MHz.

Reproduce: section 1 (`run_bench.sh exact --width 16 --n 10000` + `run_real.sh --width 16
--skip-rtl`, `run_syn.sh exact --width 16 --period 2.4 --signoff --sta-period 2.5`,
`run_power.sh exact --width 16 --clock 2.5 --syn-period 2.4 --sdf`, and `run_syn.sh exact
--width 16 --period 1.8` + `sta/run_batch.sh exact_w16_ss_p1.8:ss:max:2.0` for the minimum
period). Smoke test of a 16-bit approximate multiplier: `run_bench.sh mb:park_14z --width 16
--n 16` gives 0/16 bit-exact, 45.91 dB PSNR vs the INT16 golden, labels 16/16 and RTL ==
emulation 16/16 (`bench/results/mb_park_14z_w16_n16.md`).

Limits: pre-layout, ideal clocks; the root clock net (4.09 pF before CTS) is not in the power
totals, as for the 8-bit chip.
