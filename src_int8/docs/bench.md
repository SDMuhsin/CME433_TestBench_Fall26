# RTL-run benchmark: byte-LM quality of `mq_chip` per INT8 multiplier

The task metric for approximate-multiplier studies is the language-model quality of the
**accelerator's own output**: bits per byte (BPB) and per-byte perplexity (PPL = 2^BPB) of the
next-byte predictions that the Verilator simulation of the full `mq_chip` RTL produces on
held-out text. Python only prepares the inputs (byte crops, the token-independent stream image)
and scores the 128 INT16 logits read back from the simulated chip. The multiplier under test is
`mq_mul8` (`docs/mul8_swap.md`).

```
src_int8/bench/run_bench.sh <variant> [--n 512] [--length 1024] [--jobs nproc-4]
    <variant> = exact | <name> (src_int8/bench/variants/<name>.v or <name>/*.v) | path to .v / dir
-> build/bench/runs/<variant>_c<n>x<length>/results.{md,json}, copied to
   src_int8/bench/results/<variant>_c<n>x<length>.{md,json}
python3 -m src_int8.bench.emu.run <variant> build/bench/c512x1024 [--n 64]   # software screen (minutes)
```

## Design

| Item | Choice |
|---|---|
| Data | TinyStories V2 (GPT-4) **validation** split, `data/tinystories/val.bin` (`scripts/prep_tinystories.sh`). Training used the train split only; the validation split was only printed as a monitor during float / QAT training (`src/model/train.py`, `model/train/*.py` save the final step, no checkpoint selection), so it is held out. |
| Crops | `eval_segments(val.bin, n, 1024, seed 1234)` (`model/data/batches.py`): n random 1,025-byte crops, 1,024 scored predictions each. The first 256 are exactly the crops of every BPB number in `docs/model.md` (golden **1.3749**), and the crop set is prefix-stable (the first k crops of a larger n are the k-crop set). Crops are random, not strictly disjoint: 14 adjacent pairs of the 512 overlap (1.4 % of bytes shared; 47 pairs / 2.5 % at 1,024), always with a different context because the state is reset per crop. |
| Per crop | `STATE_RESET` with the first byte, then 1,024 forced bytes on the chip (`tb_mq_demo` over named pipes, `demo/host/chip_link.py`); cycle counts and TB errors are recorded per crop. Identical to `golden.host.evaluate` (state reset per crop, host log-softmax in float64). |
| Parallelism | `nproc - 4` = 44 independent Verilator processes (`bench/worker.py`), crop i on worker i mod 44, each process running its crops back to back with a reset between them; resumable per crop. No tracing; `-O3`, `-march=native`. |
| Python reference | Exact golden `HwModel` on the same crops (`bench/ref.py`, ~3 min for 1,024 crops), compared logit by logit. For a non-exact variant, also the emulator (`bench/emu/`): the golden with every `mq_mul8` product taken from the variant's 256 x 256 table, which is extracted by exhaustive iverilog simulation of the variant's Verilog (~3 min for 512 crops). |
| Statistics | BPB = mean over crops of the per-crop mean NLL (equal-length crops). SE and 95 % CI: bootstrap over whole crops (4,000 resamples, seed 0), which respects the strong within-crop correlation. Variants are compared to the exact baseline **paired** on the same crops (bootstrap of the per-crop difference); the paired SE is far below the absolute SE. |

## Throughput and the choice of N

Single process: 0.19 s per token (2.4 M simulated clk/s, 450,412 clk per token). With 44
processes on the 24-core / 48-thread host: 0.43 s per token per process, about 102 tokens/s in
total (hyper-threading), i.e. 7.3 min per 44-crop round.

| Crops n | Bytes scored | Abs. SE of BPB (exact) | Wall, 44 workers |
|---:|---:|---:|---|
| 88 | 90,112 | 0.0165 | 15.6 min (measured, `results/example_trunc4_c88x1024.json`) |
| 256 | 262,144 | 0.0102 | ~45 min (6 rounds) |
| **512 (default)** | **524,288** | **0.0075** | **~90 min (12 rounds)** |
| 1,024 | 1,048,576 | 0.0055 | 180.6 min (measured, `results/exact_c1024x1024.json`) |

The absolute SE is dominated by the crop-to-crop variation of the text (per-crop BPB std
0.17), which is common to all variants; the quantity that decides between two multipliers is the
paired difference on the same crops. Its SE is much smaller and scales with how unevenly a
variant hurts: a probe multiplier that clears only the product LSB (|error| <= 1) costs
+0.0023 +- 0.0004 BPB on the 512 crops (one-off emulator probe, not a committed variant),
and the crude `example_trunc4` costs +0.441 +- 0.005 on 88 crops. With n = 512 a 0.01 BPB
difference is therefore resolved at well over 10 paired standard errors, and the absolute
BPB is known to +- 0.015 (95 %); ~1.5 h per variant is the chosen trade-off (1,024 crops halve
the absolute variance for 3 h). `--n 256` reproduces the crops of the 1.3749 number in ~45 min.

## Baseline (exact `mq_mul8`)

| Run | Crops | RTL BPB +- SE (95 % CI) | PPL / byte | Python golden, same bytes | Logits RTL vs golden | Artefact |
|---|---:|---|---:|---:|---|---|
| exact | 1,024 | 1.3891 +- 0.0055 (1.3782..1.4000) | 2.6192 | 1.3891 | 0 / 1,048,576 tokens differ | `bench/results/exact_c1024x1024.json` |
| exact, first 512 (**baseline for the default n**) | 512 | **1.3843 +- 0.0075** (1.3695..1.3992) | **2.6104** | 1.3843 | 0 / 524,288 | `bench/results/exact_c512x1024.json` |
| exact, first 256 (= `docs/model.md` crops) | 256 | **1.3749** +- 0.0102 (1.3554..1.3949) | 2.5935 | 1.3749 | 0 / 262,144 | `bench/results/exact_c1024x1024.json` (`head256`) |

The RTL reproduces the golden 1.3749 BPB exactly: all 1,048,576 x 128 logits read back from the
simulated chip equal the Python bit-exact model's, every token took 450,412 clk START -> done,
and the TB reported no error. The 512-crop baseline is the first 512 crops of the 1,024-crop run
(the crop set is prefix-stable), so it was not simulated twice. The BPB rises with n (1.3749 ->
1.3843 -> 1.3891) because the crops are random samples of text of varying difficulty; it is within
the absolute CIs, and comparisons are always made on identical crops.

## Sanity check of the harness on an approximate variant

`variants/example_trunc4.v` (exact product with its 4 LSBs cleared, |error| <= 15, a template,
not a proposal), `run_bench.sh example_trunc4 --n 88`: RTL BPB 1.8333 +- 0.0174, +0.4408 +- 0.0047
vs the exact baseline on the same 88 crops (paired); the emulator's logits equal the RTL's on all
90,112 tokens, which also confirms that `mq_mul8` carries exactly the products the emulator
replaces (`docs/mul8_swap.md`) and nothing else. Cycles stayed 450,412 per token.

## Files

| Path | Role |
|---|---|
| `bench/run_bench.sh` | the one command per variant |
| `bench/build.sh` | Verilator build with the variant in place of `rtl/int/mq_mul8.v` |
| `bench/prep.py`, `bench/ref.py` | crops + stream tables; exact golden logits / NLL on the crops |
| `bench/worker.py` | one chip simulation over its share of the crops (logits per crop, resumable) |
| `bench/score.py`, `bench/stats.py`, `bench/common.py` | NLL from INT16 logits, bootstrap SE / CI, paired deltas, report |
| `bench/emu/` | software screen: exhaustive table of the variant (iverilog), golden with the table patched in |
| `bench/variants/` | student `mq_mul8` designs (`example_trunc4.v` template) |
| `bench/results/` | committed results (`<variant>_c<n>x<length>.{md,json}`) |
