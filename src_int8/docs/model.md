# INT8 model: QAT recipe and results

Status: 2026-10-14. Team A deliverables A1-A6 of `plan.md` are done; the shipped parameters are
`golden/params/mamba_e96_int8.npz` (exported from `model/checkpoints/mamba_e96_qat.pt`).

## 1. Starting point

The FP16 chip's checkpoint `mamba_e96.pt` (`src/model/train.py` recipe: 20k steps, batch 64 x 512,
AdamW, peak LR 3e-3, d_inner 96, seed 0; 50,048 parameters). Its float BPB on the 256 x 1024-byte
validation crops (`eval_segments(seed 1234)`) is **1.3546**, the FP16 golden's is **1.3549**.
Running the same checkpoint through the INT8 fake quantisation without any training gives
**1.5412** (+13.8 %): the INT8 formats of spec table 3.1 are far too coarse for post-training
quantisation of a 50k-parameter model, so QAT is required.

## 2. QAT (`model/qat/`, `model/train/qat.py`)

`model/qat/qmamba.py::q_forward` is the float forward of `MambaLM` with every tensor of spec
table 3.1 fake-quantised where the chip stores it, exactly as section 9 prescribes:

| What | How (`model/qat/ste.py`) |
|---|---|
| Activations XN, XI, XC, U, DL / B / C, DT_PRE, DT, DA, Y, Z, SZ, G, X, LOGITS, R | `fq(x, fmt)`: clip to the format range, round to its LSB, straight-through gradient (`golden/ops/formats.py` is the single copy of the table) |
| Weights W_in (norm gain folded in), W_x, W_dt, W_out, E_out (final gain folded in) | `fq_rows`: per-row symmetric INT8, `s_row = max|w| / 127` recomputed every step from the float weights, scale detached |
| conv w0 / w1 | `fq_rows` on `[E, 2]`: one scale per channel |
| cb, b_dt, E_in (Q7.8), D (INT8 2^-6), A' (Q8.7, clamped to [-256, -2^-7]) | `fq` with the 3.2 formats |
| Nonlinearities | sigmoid / softplus evaluated in float on the LUT input range [-8, 8], output rounded to Q0.15 / Q3.12 (softplus saturates at 8 - 2^-12); dA = round(2^(dt A') 2^15) / 2^15 with `dt A' <= -16 -> 0`; rsqrt rounded to Q6.9 |
| Scan | chunked parallel scan on the fake-quantised dA (`model/float/scan.py::scan_with_decay`), state clipped to +-64 at every position, no per-step rounding (the golden measures that gap) |

What is not modelled in training, by design (spec 9): the LUT interpolation error (<= 2.1e-4
sigmoid, 2.7 LSB softplus, 4.7 LSB dA, 3.6e-4 rsqrt), the (M, s) approximation of the requant
ratio (2^-14 relative) and the INT24 recurrence rounding. Section 4 shows these cost 0.0009 BPB.

Recipe: AdamW (betas 0.9 / 0.95, weight decay 0.01), batch 64 x 512, linear warm-up 200 steps then
cosine to 0, grad clip 1.0, seed 0, `torch.compile`, 94 ms / step on an RTX 6000 Ada class GPU.

| Run | Steps | Peak LR | Fake-quant BPB (256 x 1024) | Golden BPB | vs FP16 golden 1.3549 | Time |
|---|---|---|---|---|---|---|
| spec 9 default | 5,000 | 3e-4 | 1.4091 | 1.4092 | +4.0 % (misses 1.3955) | 4.7 min |
| knob: steps | 20,000 | 3e-4 | 1.3920 | - | +2.7 % | 18.6 min |
| **knob: steps + LR (shipped)** | **20,000** | **1e-3** | **1.3740** | **1.3749** | **+1.5 %** | 16.5 min |

The 5k-step default of spec 9 misses the acceptance figure; both permitted knobs were needed
(spec 9 allows up to 20k steps and a peak LR of 1e-4..1e-3). The format table was not changed.
Checkpoints: `model/checkpoints/mamba_e96_qat.pt` (shipped), `mamba_e96_qat_5k_lr3e-4.pt` (the
default recipe, kept for reference).

Reproduce (repo root; `train.bin` / `val.bin` from `python3 -m src_int8.model.data`):

```
python3 -m src_int8.model.train.qat --ckpt mamba_e96.pt --train-bin train.bin --val-bin val.bin \
    --out src_int8/model/checkpoints/mamba_e96_qat.pt --steps 20000 --lr 1e-3 --device cuda:1
python3 -m src_int8.model.evaluate mamba_e96.pt val.bin                                   # float 1.3546
python3 -m src_int8.model.evaluate src_int8/model/checkpoints/mamba_e96_qat.pt val.bin --qat   # 1.3740
python3 -m src_int8.golden.io.weights src_int8/model/checkpoints/mamba_e96_qat.pt src_int8/golden/params/mamba_e96_int8.npz
python3 -m src_int8.golden.host.evaluate src_int8/golden/params/mamba_e96_int8.npz val.bin   # golden 1.3749
```

## 3. Export (`golden/io/weights.py`)

Norm gains folded (W_in rows, E_out), A' = -exp(A_log) log2 e, per-row INT8 with the 3.2 rule,
(M, s) per row from the exact float64 ratio (3.3), all ranges asserted on save and on load.
Shipped parameter facts: requant shifts s in 16..24 (all far inside 1..47), every weight row uses
the full +-127 range, E_in in [-305, 407] (Q7.8, |x| < 1.6), 8 of 768 A' entries clipped at -256
(float values -256.0004..-256.003; irrelevant since dt A' < -16 there gives dA = 0), one D
channel at the 127/64 limit (1.9844, which the QAT clipped it to). The float32 fake quantisation
of training and the float64 exporter agree on every INT8 weight except one exact .5 tie
(`E_out[108, 29]`, w / s = 107.5000002); the exporter is the authority and the golden tests
dequantise its integers.

## 4. Golden model (`golden/`)

Pure int64 numpy, no float in the token step. Layer ops follow spec 5.2 op for op
(`golden/layers/`), with lane and accumulator asserts (`golden/ops/lane.py`) on every step: the
operand ranges of spec 5 bound every partial sum below 2^31, and the asserts stayed silent over all
runs (2.1 M tokens of long context, 262 k tokens of BPB evaluation, random legal parameters).

| Measurement (256 x 1024 crops) | BPB |
|---|---|
| float e96 (FP16 chip's checkpoint) | 1.3546 |
| FP16 chip golden | 1.3549 |
| QAT checkpoint, fake-quant forward (torch) | 1.3740 |
| **INT8 integer golden (shipped)** | **1.3749** |
| acceptance (1.3549 x 1.03) | 1.3955 |

The golden-to-fake-quant gap (+0.0009 BPB, +0.07 %) is the sum of LUT interpolation, (M, s)
rounding and the per-step INT24 recurrence rounding that the chunked training scan cannot model.
Per token the two differ at the LSB level (a 1-LSB flip in XN moves XI by 0.25 LSB, an XI flip
moves XC by 8 LSB, a DL flip moves DT_PRE by 60 LSB), so the layer tests compare each golden op
against the torch op on identical integer inputs (1 LSB, 3 LSB for softplus, 5 LSB for dA) and
the model-level comparison is statistical (`golden/tests/test_e2e.py`).

Golden samples (T = 0.8, seed 0; `python3 -m src_int8.golden.host.generate`):

```
Once upon a time baby. They wanted the morning, and the man looked at the car and don't know you?"
The tells trucking to stone and soft fit for a mother, went how to Max and the ground. Tim was very o

Lily wanted to stay will on the bird." The bird was not the sun.
In the day tired the fox. The cat and Momo went to the road the teacher tiger. Then, something unexpected happened.
```

## 5. Long context (`longctx/`, `docs/long_context.md`)

256 crops x 8,192 bytes with the state carried (no reset, stories joined by EOS): golden
**1.3790** BPB, the QAT fake-quant torch model on the same crops 1.3781 (+0.07 %, the same gap as
at 1k, flat across every position bucket), float64 unclipped recurrence of the same weights 1.3895
(the QAT model learned to use the chip's clips, so the unclipped float is the worse model). The
INT24 state peaks at |h| = 26.6 of 64 with **zero saturations** over 2.1 M tokens x 768 entries,
and the Q0.15 dA never saturates at 1 - 2^-15 (that needs tau > 756k tokens).

## 6. Tests

```
python3 -m pytest src_int8/golden/tests              # 55 tests, ~100 s (e2e BPB included)
python3 -m pytest src_int8/golden/tests -m "not e2e"  # ~5 s
```

| File | Covers |
|---|---|
| `test_formats.py` | `rsh` ties (both signs, exhaustive vs the definition), `sat` at 8 / 16 / 24 / raw, the table 3.1 / 3.2 values |
| `test_lane.py` | `mac` operand and accumulator asserts, `dot` == sequential MACs with `ps`, `wb_sh`, `wb_rq` vs definition (10k random), RQ bounds, saturation at each width, negative ties |
| `test_nlu.py` | ROM layout and anchors, address edges (clamps, `f = 2^11`, exp2 zero flag, rsqrt normalisation), accuracy: all 4,097 uniform inputs, all 2^19 exp2 fractions in 3 octaves, all 2^17 rsqrt mantissas at 3 exponents, SiLU |
| `test_stream.py` | 54,280 B, row sizes, byte 196 = w1[0] (197 B window), random and shipped round trip, memory map and host image |
| `test_weights.py` | row scale rule, (M, s) octaves and the 2^15 carry, spec scales per row class, fixed-format saturation, exporter asserts on random floats and on the shipped set |
| `test_layers.py` | every layer op vs the QAT torch op on identical inputs over 72 tokens (both blocks) |
| `test_model.py` | stream view == parameter view, batched == single, reset, formats of logits and state, random legal parameters never overflow, greedy text, seeded sampler |
| `test_e2e.py` | golden BPB <= 1.3955 on the 256 x 1024 crops; golden vs fake-quant within 1 % on a subset |
