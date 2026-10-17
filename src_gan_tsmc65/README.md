# src_gan_tsmc65: the INT8 GAN accelerator for 65 nm

A technology-clean copy of the `dla_e2e_chip` RTL (the 64-256-256-784 G300 generator; see `docs/dla_e2e_chip.md`), plus a bit-exact Fashion-MNIST benchmark for approximate multipliers. Legacy `rtl/` and `scripts/` are not touched.

## Layout
| Dir | Contents |
|---|---|
| `rtl/` | `gan65.f` file list. Top `top/gan65_chip.v`: same logic as `dla_e2e_chip`, but plain `io_in/io_out/io_oe` instead of GF180 pad terminals |
| `rtl/pe/gan_mul8.v` | **The multiplier swap point**: signed 8x8 to 16 bit, used by all 16 PEs (`a` = weight, `b` = activation) |
| `rtl/mem/` | `dla_sram_1rw_256x8` as a 256x8 latch register file (`gan65_latch_rf` + `gan65_icg`) in place of the GF180 SRAM macro. `*_sim.v` is a fast flip-flop model, used only for simulation |
| `model/fmnist/` | int8 Fashion-MNIST generator (`G300_*.memh`), requant CSRs (`csr.memh`), quantisation record (`quant.json`), float generator (`G300_float.npz`), 256 benchmark latents, reference vectors |
| `golden/` | Bit-exact integer model of the chip (`model.py`), tanh ROM search, latent generator, self-check |
| `classifier/` | Small Fashion-MNIST CNN (`fmnist_cnn.npz`, 91.35 % test accuracy), used to label the generated images |
| `bench/` | `run_bench.sh`, Verilator build, pad-level host TB, scorer, multiplier variants; `run_real.sh` + `real/`: FID / IS / KID / precision-recall against real Fashion-MNIST |
| `docs/bench.md` | Benchmark method and results |
| `syn/` `lec/` `sta/` `sim/gls/` | 65 nm flow on the server: DC topographical, Formality, PrimeTime, VCS gate-level sim; `syn/run_syn.sh <variant>` synthesises one multiplier variant. The kit config is shared with `src_int8_tsmc65` (`site/README.md`) |
| `power/` | PrimePower (averaged, SAIF of one image from zero-delay or SDF-timed GLS); `power/run_power.sh <variant>` gives power and energy per image of one variant |
| `docs/results.md` | **Camera-ready summary**: bit-exactness, timing at 3 corners, area and power split (PE array, multipliers, latch RF), energy per image, variant comparison |
| `docs/synthesis.md`, `results/` | Fmax sweep, signoff (DC 1.8 ns, PT 2.0 ns = 500 MHz), area split, FM / PT / GLS results; summary files |

## Run
```bash
src_gan_tsmc65/bench/check_mem.sh                         # latch RF == fast memory model (unit)
python3 -m src_gan_tsmc65.golden.check_ref                # golden model == reference vectors
src_gan_tsmc65/bench/run_bench.sh                         # exact multiplier, 256 latents (~1 min)
src_gan_tsmc65/bench/run_bench.sh my_mul                  # bench/variants/my_mul.v (module gan_mul8)
src_gan_tsmc65/bench/run_bench.sh mq:ilm                  # any src_int8/bench/variants mq_mul8 variant
src_gan_tsmc65/bench/run_real.sh                          # 10k RTL images per variant, GAN metrics (~3 h)
```
To add a multiplier, copy `bench/variants/example_trunc4.v`, keep the module name `gan_mul8` and its ports, and pass the file name (or a path) to `run_bench.sh`. The results are written to `build/gan65/runs/<variant>_n<N>/` and summarised in `bench/results/<variant>_n<N>.md`.

Synthesis (on the server, in the repository clone; docs/synthesis.md):
```bash
src_gan_tsmc65/syn/run_syn.sh exact --signoff             # DC ss 1.8 ns + Formality + PT ss/tt/ff at 2.0 ns
src_gan_tsmc65/syn/run_syn.sh my_mul --signoff            # same for bench/variants/my_mul.v
src_gan_tsmc65/power/run_power.sh exact --sdf             # GLS of one image (SDF, tt) + PrimePower tt at 500 MHz
src_gan_tsmc65/power/run_power.sh my_mul --clock 2.5 --syn-period 2.4 --sdf   # variant at 400 MHz
```
Headline (exact, tt, 500 MHz, pre-layout): 182,751 um^2, 11.2 mW, 52.5 uJ per image, 213 images/s; the latch RF and its clock gating take 83 % of the power, the 16 multipliers 3 % (`docs/results.md`).

Needs Verilator 5 (or set `VERILATOR=`), iverilog, and Python 3 with numpy, torch and Pillow.
