# Demo: TinyStories text generated on `mb_chip`

Three stories from the 2-block Mamba byte-LM. Each story starts from zero state. The host samples at temperature 0.8 with a fresh fixed-seed RNG (`HostSampler(0.8, seed=0)`). Generation stops at byte 0x00 (EOS) or at 200 bytes total. None of the three hit EOS before the limit.

> **Once upon a time**, a pretty and bright on owner. He loved to move our an inside the top, his music on the surprised. It was very party sad. One day, the strange playing gone, the frog was walking. The

> **Lily wanted** to stay wing on, Spot saw the delicious can the stick and again. He felt playing together, "Wow!" he said. "That sound is okay!" The cat was their hold in the ignorant. Tim was very happy

> **The little dog** named Spot was very exciting. She loved to look lots of peaced. The bird sailor it together own work to play with the beautiful for scary.<br>One day, the man branches and hugged them and

The prompt is in bold. The `<br>` marks a 0x0A byte that the model generated. The model has 50k parameters, so expect TinyStories vocabulary and rhythm, not coherent plots.

## How the chip run proves the text (closed loop)

`run_demo.sh` runs the RTL `mb_chip` in iverilog through `tb/tb_mb_demo.sv`. This TB is a pad-level QSPI host that reuses `src/tb/chip/qspi_host.svh`. A Python host (`host/closed_loop.py`) drives the TB over two named pipes:

1. The host sends the next byte, plus a STATE_RESET flag on the first byte of a story.
2. The TB issues START and streams the 99,840-byte weight stream, honouring HRDY. Only the 64-word embedding row depends on the byte. The TB waits for done, checks STATUS and the byte count, and reads back the 256 logit bytes at 0x800.
3. The host compares the 128 logits with `src/golden` (`HwModel`) bit for bit. It then samples the next byte from **the chip's** logits.
4. At the end, the host checks that the text equals the golden-only generation (`host/stories.py`).

| Module | Role |
|---|---|
| `host/stories.py` | Golden-only stories: prompts, sampler settings, `golden_story()` |
| `host/chip_link.py` | `ChipSim`: vvp subprocess and pipe protocol; stream tables for the TB |
| `host/closed_loop.py` | One story in closed loop, golden compare, `<build>/<story>.json` |
| `tb/tb_mb_demo.sv` | Pipe-driven pad-level host TB |
| `run_demo.sh` | Compile, then run the stories in parallel |

## Result (RTL, 2026-10-13)

| Story | Chip tokens | Logits bit-exact | Text == golden | TB errors |
|---|---|---|---|---|
| Once upon a time | 199 | 199 x 128 | yes | 0 |
| Lily wanted | 199 | 199 x 128 | yes | 0 |
| The little dog | 199 | 199 x 128 | yes | 0 |

**PASS: 597 tokens x 128 logits bit-exact.** Each story is 199 tokens because the last sampled byte is not fed back. Every one of the 597 tokens took the same number of cycles:

- START->done: 801,056 clk.
- Including the STATUS/count check and the logit read-back: 805,956 clk.
- HRDY dropped 195 times per token.

The wall time was about 48 minutes for the three stories in parallel, roughly 14 s of simulation per token.

## Throughput (25 MHz)

| | clk/token | ms/token | tokens/s |
|---|---|---|---|
| Chip compute (START->done) | 801,056 | 32.04 | 31.2 |
| Host loop (incl. status + 256-byte read-back) | 805,956 | 32.24 | 31.0 |

A 200-byte story therefore takes about 6.4 s on silicon. The chip is stream-bound: the QSPI weight stream sets the token time.

**Quality.** The golden hardware arithmetic gives 1.3549 bits/byte against 1.3546 for the float model (+0.02 %, `docs/spec.md` section 2). The demo text is what the FP16 chip arithmetic produces, not a float approximation.

## Long runs without reset (Verilator)

`tb/build_verilator.sh` compiles the same TB and the full `chip.f` RTL with Verilator 5. The binary is a drop-in replacement for the `.vvp` image in `ChipSim`: it takes the same plusargs and pipes and gives the same 801,056 clk per token, at 0.35-0.75 s per token. `host/long_run.py` feeds >1k tokens with only one STATE_RESET, at token 0. It runs either in forced-input mode (corpus bytes, crossing story EOS bytes) or in closed loop (sampling through EOS). Every token is checked bit-exact against golden.

Results:
- 2,048 + 8,192 forced tokens and 1,200 closed-loop tokens, all bit-exact.
- `run_long.sh val.bin` does the 2,048 + 1,200 pair.

Details are in `../docs/long_context.md`.

## Reproduce (from the repo root)

```
python3 -m src.demo.host.stories                 # golden-only stories (~5 s)
src/demo/run_demo.sh                        # closed loop on the RTL chip, 3 x 199 tokens (~50 min)
src/demo/run_demo.sh --max-bytes 20 --prompt "Lily"   # quick check (~4 min)
```

Both commands need iverilog/vvp on PATH and a python3 with numpy. The scripts fall back to `/usr/bin/python3` if the default python3 has no numpy. Outputs go to `src/demo/build/` (git-ignored): per story `<story>.json` (text, per-token cycles and mismatches), `<story>/host.log` and `<story>/vvp.log`. The script exits 0 only if every story passes.
