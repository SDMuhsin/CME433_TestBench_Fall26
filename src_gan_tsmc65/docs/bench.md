# gan65_chip: Fashion-MNIST approximate-multiplier benchmark

`bench/run_bench.sh [variant]` runs the full `gan65_chip` RTL on generator latents in Verilator, then compares every generated image with a bit-exact Python model of the chip. The only thing a student changes is the multiplier, `rtl/pe/gan_mul8.v`, which all 16 PEs of all three layers use.

## Method
1. **Model.** The 64-256-256-784 MLP generator (ReLU, ReLU, Tanh) was trained on Fashion-MNIST and quantised to per-tensor int8 with static requant multipliers, so one set of CSRs serves every latent (`model/fmnist/quant.json`). Over 8 latents, the int8 output differs from float by 2.18/255 grey levels (MAD).
2. **Latents.** There are 256 latents: z = `torch.randn(256, 64)`, seed 2000, quantised with the model's sZ (`golden/latents.py`, `model/fmnist/latents.memh`).
3. **Chip simulation.** Verilator 5.044 builds `bench/tb/gan65_bench_tb.sv`, a pad-level host that uses only `sclk`/`cs_n`/`io[3:0]`/`hrdy`. It writes the six requant CSRs once. Then, for each latent, it sends START, streams the full 283,984 B (zq + all weights and biases) at SCLK = clk/4 while honouring HRDY, waits for done, checks STATUS and reads the 784 pixels back over RD_PIX_Q. The latents are split across parallel simulations (default nproc-4).
4. **Golden.** `golden/model.py` is the integer model: 24-bit wrapping accumulators, the `e2e_requant` shift/round/saturate and the tanh-ROM binary search, with the ROM parsed from the RTL. `golden/check_ref.py` checks it against the 8 reference vectors of the quantisation flow: 8/8 images, 784/784 pixels each.
5. **Emulation.** For a non-exact variant, iverilog derives the variant's 256x256 product table from its Verilog. The golden model is then rerun with that table. If the RTL output equals this emulation, the run measured the multiplier and not a harness fault.
6. **Scoring** (`bench/score.py`, on uint8 grey levels):
   - bit-exact images and pixels against the exact golden;
   - PSNR against the golden, computed over all pixels, with worst and median per image (inf when exact);
   - MAE and maximum absolute error;
   - label agreement: `classifier/fmnist_cnn` labels each RTL image and the matching golden image, and the score counts equal labels. The classifier is a 2-conv CNN with 91.35 % accuracy on the Fashion-MNIST test set, trained in 23 s on one A40.

## Memory model
`rtl/mem/dla_sram_1rw_256x8.v` is the synthesis memory: a latch RF with one ICG per word, 2,048 clock gates in total. It simulates 130-170x slower (136-170 s per image in Verilator against about 1 s), so the benchmark defaults to `rtl/mem/dla_sram_1rw_256x8_sim.v`, a flip-flop array with the same cycle behaviour. Two checks show the models are equivalent:
- `bench/check_mem.sh`: 200,000 random cycles with a mix of hazard addresses, PASS;
- `run_bench.sh exact --n 16 --latch-rf`: the full chip with the latch RF, 16/16 images bit-exact.

## Results (256 latents, 2026-10-17)
| Variant | Bit-exact images | PSNR (dB) all / worst / median | MAE / max (grey levels) | Label agreement | RTL == emulation |
|---|---|---|---|---|---|
| `exact` (rtl/pe/gan_mul8.v) | 256/256 | inf / inf / inf | 0 / 0 | 256/256 (100 %) | n/a |
| `mq:evo_1KV8` (EvoApprox, exact) | 256/256 | inf / inf / inf | 0 / 0 | 256/256 (100 %) | 256/256 |
| `mq:ilm` | 0/256 | 33.10 / 22.59 / 34.33 | 2.58 / 142 | 250/256 (97.7 %) | 256/256 |
| `example_trunc4` | 0/256 | 24.65 / 19.23 / 25.22 | 8.96 / 135 | 243/256 (94.9 %) | 256/256 |
| `mq:evo_1KR8` | 0/256 | 21.42 / 15.47 / 21.68 | 12.49 / 220 | 224/256 (87.5 %) | 256/256 |
| `mq:evo_1KVL` | 0/256 | 12.19 / 8.26 / 12.40 | 43.33 / 253 | 131/256 (51.2 %) | 256/256 |
| `mq:evo_1KR3` | 0/256 | 8.60 / 7.08 / 8.48 | 86.42 / 240 | 21/256 (8.2 %) | 256/256 |

The full per-variant tables, including classifier confidence, are in `bench/results/<variant>_n256.md`.

Over the 256 latents, the golden labels are: T-shirt/top 14, Trouser 27, Pullover 13, Dress 36, Coat 25, Sandal 18, Shirt 50, Sneaker 27, Bag 21, Ankle boot 25. Mean classifier confidence on the golden images is 0.814.

**Cost.** One image takes 2,346,721 clk, or 93.9 ms at 25 MHz. That covers START, the stream and the readback, and the stream dominates. With the fast memory model, Verilator takes about 1 s of CPU per image. On 44 parallel jobs, 256 images simulate in 12 to 21 s, and the whole `run_bench.sh` takes about 1 min, including the build (about 50 s the first time for each variant) and the scoring.

The image error tracks the multiplier's **bias on the operands the chip actually uses**, not its mean error. Layers 2 and 3 multiply weights by non-negative activations (h0 and h2 lie in [0, 127]), so a signed error that cancels over the full input range can still accumulate over 256 terms per output.

The table below gives each variant's product error over all 65,536 inputs (`bench/mul_table.py`) and over the half with b >= 0:

| Variant | MAE / bias, all inputs | MAE / bias, b >= 0 | PSNR (dB) |
|---|---|---|---|
| `mq:ilm` | 113.7 / 0.0 | 113.7 / 0.0 | 33.10 |
| `example_trunc4` | 6.5 / -6.5 | 6.5 / -6.5 | 24.65 |
| `mq:evo_1KR8` | 32.0 / +0.25 | 31.8 / -31.8 | 21.42 |
| `mq:evo_1KVL` | 101.3 / -16.3 | 112.3 / -112.3 | 12.19 |
| `mq:evo_1KR3` | 2016 / +15.8 | 2000 / -2000 | 8.60 |

ILM has the largest MAE of the useful variants but no bias, and it gives the best images. Rank candidates with this benchmark, not with the error statistics of the multiplier alone.

![exact](img/grid_exact.png)
*First 64 images, exact multiplier (identical to golden).*

![ilm](img/grid_mq_ilm.png)
*Same latents with `mq:ilm`.*

## Reproduce
```bash
python3 -m src_gan_tsmc65.golden.check_ref
src_gan_tsmc65/bench/check_mem.sh
for v in exact mq:evo_1KV8 mq:ilm example_trunc4 mq:evo_1KR8 mq:evo_1KVL mq:evo_1KR3; do src_gan_tsmc65/bench/run_bench.sh $v; done
src_gan_tsmc65/bench/run_bench.sh exact --n 16 --jobs 16 --latch-rf
python3 -m src_gan_tsmc65.classifier.train          # retrain the classifier (cuda:1, ~25 s)
```
