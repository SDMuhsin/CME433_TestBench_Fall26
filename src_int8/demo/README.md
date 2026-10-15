# Demo: TinyStories text generated on `mq_chip`

Three stories (plus the "The quick brown fox" prompt) from the INT8 2-block Mamba byte-LM. Each
story starts from zero state. The host samples at temperature 0.8 with a fresh fixed-seed RNG
(`HostSampler(0.8, seed=0)`). Generation stops at byte 0x00 (EOS) or at 200 bytes total.

> **Once upon a time** baby. They wanted the morning, and the man looked at the car and don't know you?"<br>The tells trucking to stone and soft fit for a mother, went how to Max and the ground. Tim was very o

> **Lily wanted** to stay will on the bird." The bird was not the sun.<br>In the day tired the fox. The cat and Momo went to the road the teacher tiger. Then, something unexpected happened. The sun, the monkey

> **The little dog** in the price toy. They raring a new tree to the sun.

> **The quick brown fox**. A mouth sandwich had funny new toys. He said, "Will do you can on the look your good!"<br>Tim were very sad said, "Why is it?" The little girl was a grand. Tim and the sun went to th

The prompt is in bold. The `<br>` marks a 0x0A byte that the model generated. "The little dog"
sampled EOS after 67 bytes. The model has 50k parameters, so expect TinyStories vocabulary and
rhythm, not coherent plots.

## How the chip run proves the text (closed loop)

`run_demo.sh` runs the RTL `mq_chip` (Verilator by default, `--iverilog` for the 4-state image)
through `tb/tb_mq_demo.sv`. This TB is a pad-level QSPI host that reuses `src_int8/tb/common/qspi_host.svh`.
A Python host (`host/closed_loop.py`) drives the TB over two named pipes:

1. The host sends the next byte, plus a STATE_RESET flag on the first byte of a story.
2. The TB issues START and streams the 54,280-byte weight stream, honouring HRDY. Only the
   128-byte embedding row (64 x INT16 LE) depends on the byte. The TB waits for done, checks
   STATUS and the byte count, and reads back the 256 logit bytes at 0x1040 (INT16 Q7.8, LE).
3. The host compares the 128 logits with `src_int8/golden` (`HwModel`) bit for bit. It then
   samples the next byte from **the chip's** logits (`logits / 256` into the float64 sampler).
4. At the end, the host checks that the text equals the golden-only generation (`host/stories.py`).

| Module | Role |
|---|---|
| `host/stories.py` | Golden-only stories: prompts, sampler settings, `golden_story()` |
| `host/chip_link.py` | `ChipSim`: simulator subprocess and pipe protocol; stream tables for the TB (written atomically: parallel hosts share them) |
| `host/closed_loop.py` | One story in closed loop, golden compare, `<build>/<story>.json` |
| `host/long_run.py` | >1k tokens with one STATE_RESET: forced corpus bytes or closed loop, `<out>/long.json` |
| `tb/tb_mq_demo.sv` | Pipe-driven pad-level host TB |
| `tb/build_verilator.sh` | Verilator 5 build of the TB + `rtl/chip.f` (`build/verilator/tb_mq_demo`) |
| `run_demo.sh` | Build, then run the stories in parallel |
| `run_long.sh` | Build, then the long runs (2,048 forced + 1,200 closed loop; `--full` adds 8,192 forced) |

## Result (RTL, Verilator, 2026-10-14)

| Story | Chip tokens | Logits bit-exact | Text == golden | TB errors |
|---|---|---|---|---|
| Once upon a time | 199 | 199 x 128 | yes | 0 |
| Lily wanted | 199 | 199 x 128 | yes | 0 |
| The little dog | 67 (EOS) | 67 x 128 | yes | 0 |
| The quick brown fox | 199 | 199 x 128 | yes | 0 |

**PASS: 664 tokens x 128 logits bit-exact.** A 200-byte story is 199 tokens because the last
sampled byte is not fed back. Every one of the 664 tokens took the same number of cycles:

- START->done: 450,412 clk.
- Including the STATUS/count check and the 256-byte logit read-back: 455,312 clk.
- HRDY dropped 387 times per token (the three RMSNorms and the per-channel scan loop, `docs/rtl_units.md`).

Wall time: about 1 min for the four stories in parallel, 0.2-0.3 s of simulation per token
(iverilog: ~15 s per token).

## Throughput (25 MHz)

| | clk/token | ms/token | tokens/s |
|---|---|---|---|
| Chip compute (START->done) | 450,412 | 18.02 | 55.5 |
| Host loop (incl. status + 256-byte read-back) | 455,312 | 18.21 | 54.9 |

A 200-byte story therefore takes about 3.6 s on silicon (FP16 `mb_chip`: 6.4 s). The chip is
stream-bound: the 54,280-byte QSPI weight stream (434,240 clk at 8 clk per byte) sets the token
time; the remaining 16k clk are HRDY back-pressure.

**Quality.** The golden integer arithmetic gives 1.3749 bits/byte against 1.3546 for the float
model (+1.5 %, `docs/model.md`). The demo text is what the INT8 chip arithmetic produces, bit for
bit; it is not the FP16 chip's text (different weights after QAT), even though the prompts and
the sampler seed are the same.

## Long runs without reset (Verilator)

`host/long_run.py` feeds >1k tokens with only one STATE_RESET, at token 0, either in forced-input
mode (corpus bytes, crossing story EOS bytes) or in closed loop (sampling through EOS). Every
token is checked bit-exact against golden; the host also tracks the golden state magnitude.

| Run | Tokens | EOS crossed | Logits bit-exact | max abs h | INT24 saturations |
|---|---|---|---|---|---|
| Forced, val.bin[5000379:+2048] | 2,048 | 3 | 2,048 x 128 | 17.52 | 0 |
| Forced, val.bin[12000432:+8192] | 8,192 | 10 | 8,192 x 128 | 22.94 | 0 |
| Closed loop, "Once upon a time", T 0.8, seed 0 | 1,200 | 2 | 1,200 x 128 | 12.49 | 0 |

All PASS; details in `../docs/long_context.md` section 3.

## Reproduce (from the repo root)

```
python3 -m src_int8.demo.host.stories                 # golden-only stories (~5 s)
src_int8/demo/run_demo.sh                             # closed loop on the RTL chip, 4 stories (~1 min)
src_int8/demo/run_demo.sh --iverilog --max-bytes 20 --prompt "Lily"   # 4-state quick check (~2 min)
src_int8/demo/run_long.sh val.bin [--full]            # 2,048 forced + 1,200 closed loop [+ 8,192 forced] (~10 / 35 min)
```

`val.bin` comes from `python3 -m src_int8.model.data`. The scripts need a python3 with numpy
(they fall back to `/usr/bin/python3`) and Verilator 5 (`$VERILATOR`, PATH, or the nix store) or
iverilog. Outputs go to `src_int8/demo/build/` (git-ignored): per story `<story>.json` (text,
per-token cycles and mismatches), `<story>/host.log` and `<story>/sim.log`; per long run
`long_*/long.json` and `host.log`. The scripts exit 0 only if every run passes.
