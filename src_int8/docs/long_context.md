# Long contexts, the Q0.15 decay and the INT24 state

Status: 2026-10-14 (Team A step A6 and Team B's B7 RTL long runs, section 3). Question from
`spec.md` section 2: does the INT24 Q6.17 state with a Q0.15 decay factor hold up over long
contexts, and does it ever saturate? **Result: over 256 x 8,192 bytes with the state carried, the
integer golden is within +0.07 % BPB of the QAT model it was trained as, the gap does not grow with
position, the state peaks at |h| = 26.6 of the +-64 range with zero saturations, and the decay
never saturates. The RTL matches the golden bit for bit over 2,048 + 8,192 forced-input tokens
and 1,200 closed-loop tokens, each with a single state reset at token 0.**

## 1. BPB by position, state carried (`longctx/long_eval.py`, `report.py`)

Setup:
- **Crops.** 256 random contiguous crops of 8,192 validation bytes (`eval_segments`, seed 4321).
  Stories are joined by EOS, so the state runs across story boundaries; no reset inside a crop.
- **golden**: `HwModel`, bit-exact integer model (shipped `mamba_e96_int8.npz`).
- **fake-quant**: the QAT torch model (`q_forward`) over the whole 8,192-byte crop (chunked scan,
  state carried, same clips and rounding points as the chip, no per-step recurrence rounding).
  This is the function the weights were trained for.
- **float**: float64 exact recurrence of the same folded weights with no clipping or rounding
  (`longctx/float_ref.py`). It is a *different* function from the one trained: the QAT model
  learned to rely on the chip's clips (G at +-7.94, dt at 8, LUT inputs at +-8), so the unclipped
  float is the worse model, by 0.75 %. It is kept as the state reference (same op structure).

Overall (2.1 M predictions): golden **1.3790**, fake-quant 1.3781, float 1.3895.

| positions | golden BPB | fake-quant BPB | golden - fake-quant (95 % CI) | float BPB | max abs h hw / float | saturated INT24 | dA at 1 - 2^-15 | rel. state err vs float |
|---|---|---|---|---|---|---|---|---|
| 0-256 | 1.3973 | 1.3968 | +0.0005 +- 0.0016 | 1.4075 | 22.9 / 25.3 | 0 | 0 | 0.120 |
| 256-512 | 1.3632 | 1.3616 | +0.0016 +- 0.0017 | 1.3731 | 22.4 / 25.3 | 0 | 0 | 0.119 |
| 512-1k | 1.3702 | 1.3698 | +0.0004 +- 0.0012 | 1.3800 | 24.8 / 25.6 | 0 | 0 | 0.119 |
| 1k-2k | 1.3620 | 1.3617 | +0.0003 +- 0.0009 | 1.3729 | 23.0 / 26.0 | 0 | 0 | 0.120 |
| 2k-4k | 1.3894 | 1.3883 | +0.0011 +- 0.0007 | 1.3995 | 26.6 / 27.2 | 0 | 0 | 0.120 |
| 4k-8k | 1.3791 | 1.3779 | +0.0012 +- 0.0004 | 1.3897 | 26.5 / 26.5 | 0 | 0 | 0.120 |

- The golden-to-fake-quant gap is +0.0010 +- 0.0003 BPB overall (+0.07 %) and is the same at
  4k-8k as at 0-1k: the per-step INT24 recurrence rounding, the LUT interpolation and the (M, s)
  rounding do not accumulate. The FP16 chip's figure was +0.06 % (`src/docs/long_context.md`).
- `max abs h` is the largest |h| over all crops, channels and positions in the bucket. The INT24
  range is +-64: 2.4 bits of headroom. **0 of 2.1 M x 768 state updates saturated** (the golden
  counts `|h| == 2^23 - 1` after every step).
- The relative state error vs the unclipped float is 12 % and flat from the first bucket on; it
  is the difference between the clipped and the unclipped function (the same 12 % is seen at
  position 0-256, where no rounding history exists), not a drift of the integer state.
- The spec's `dt A' <= -16 -> dA = 0` rule fires on 1.03 % of decay evaluations; 15.6 % have
  |p| < 2^-6 (tau > 92 tokens).

Raw outputs: `longctx/results/lc_8k.md` (the `report.py --md` table with the float delta),
`longctx/results/lc_8k.log`.

## 2. Decay path accuracy (`longctx/decay.py`)

Hardware: p = dt A' (exact Q11.19), dA = exp2 LUT (32 segments of 2^(j/32), 11-bit truncated
fraction, Q0.15 output, saturating at 32767 = 1 - 2^-15). Checked on every p of a 2^-13 grid over
(-16, 0) against exact 2^p. tau = -1 / ln(dA) is the state time constant in tokens.

| true tau [tokens] | max abs err dA [Q0.15 LSB] | max rel err (1 - dA) = 1/tau | mean rel err (1 - dA) | saturated at 1 - 2^-15 |
|---|---|---|---|---|
| < 1 | 1.19 | 5.2e-5 | -1.8e-6 | 0 |
| 1-10 | 2.02 | 5.8e-4 | -5.9e-5 | 0 |
| 10-100 | 2.24 | 6.3e-3 | -8.1e-4 | 0 |
| 100-1000 | 2.12 | 1.5e-2 | -6.1e-3 | 0 |
| 1000-10000 | 0.64 | 7.7e-2 | +2.1e-2 | 0 |
| 10000-100000 | 0.18 | 6.5e-2 | +6.5e-2 | 0 |
| > 756,000 | - | - | - | all (dA = 32767, effective tau 32,768) |

- dA is accurate to 2.2 LSB of Q0.15 everywhere (the spec's bound is 4.7 LSB mid-segment); near
  p -> 0 the grid point 2^0 is exact, so slow channels get a better absolute error.
- The decay rate 1 - dA is within 1.5 % up to tau 1,000 and within 8 % up to tau 100,000, against
  20 % at tau 100-1000 and frozen above 4,110 for the FP16 chip. Saturation at 1 - 2^-15 needs
  |p| <= 1.9e-6 (tau >= 756k tokens) and never occurred in the 8k run.
- **INT24 dead band.** Free decay h <- sat24(rsh(h dA, 15)) from 97 start values in [0.01, 17]:

  | tau | dA (hw) | tokens to 1/e (min / median / max) | stuck |
  |---|---|---|---|
  | 10 | 0.904877 | 10 / 11 / 11 | 0 / 97 |
  | 100 | 0.990112 | 101 / 101 / 101 | 0 / 97 |
  | 1,000 | 0.998993 | 993 / 993 / 994 | 1 / 97 (h0 = 0.01) |
  | 3,000 | 0.999664 | 2,978 / 2,979 / 3,003 | 1 / 97 |
  | 10,000 | 0.999908 | 10,888 / 10,923 / 11,430 | 1 / 97 |
  | 30,000 | 0.999969 | 30,155 / 32,774 / 34,978 | 2 / 97 |

  Only start values at the bottom of the range (|h| = 0.01, 1,300 LSB of Q6.17) stall, and only
  for tau >= 1,000: with (1 - dA) |h| < 0.5 LSB the decay step rounds to zero, as spec section 2
  predicts (stall below |h| = 0.004 for tau 1,000). The FP16 state stalled above tau 2,000 for
  every start value and froze completely at tau 5,000.

## 3. RTL == golden over long contexts (`demo/host/long_run.py`)

The RTL ran in Verilator 5: the full `mq_chip` from `rtl/chip.f`, the pad-level QSPI host
`demo/tb/tb_mq_demo.sv` and the SRAM model, built by `demo/tb/build_verilator.sh` (0.2-0.3 s per
token, against ~15 s in iverilog). Every run shows the same 450,412 clk START->done as the
iverilog chip TB.

Each run issues one STATE_RESET at token 0 and then carries the state. Every token's 128 INT16
logits are compared with `HwModel`; the host also tracks the golden state after every token.

| Run | Tokens | EOS crossed | Logits bit-exact | TB errors | max abs h | INT24 saturations |
|---|---|---|---|---|---|---|
| Forced input, val.bin[5000379:+2048] | 2,048 | 3 | 2,048 x 128 | 0 | 17.52 | 0 |
| Forced input, val.bin[12000432:+8192] | 8,192 | 10 | 8,192 x 128 | 0 | 22.94 | 0 |
| Closed loop, "Once upon a time", T = 0.8, seed 0, sampling from the chip's logits through EOS | 1,200 | 2 | 1,200 x 128 | 0 | 12.49 | 0 |

The same corpus offsets as the FP16 chip's runs (`src/docs/long_context.md`), so the stories and
EOS crossings are the same; the INT8 state runs higher (22.9 against 16.5 for the FP16 chip at 8k)
and stays well inside the +-64 range, consistent with the golden-only 8k study above (26.6 max).
Outputs: `demo/build/long_{forced,forced_8k,closed}/long.json` + `host.log` (git-ignored).

## 4. Reproduce (repo root; `val.bin` from `python3 -m src_int8.model.data`)

```
python3 -m src_int8.longctx.long_eval src_int8/golden/params/mamba_e96_int8.npz \
    src_int8/model/checkpoints/mamba_e96_qat.pt val.bin lc_8k.npz --n 256 --length 8192 --fakeq-device cuda:1   # ~17 min CPU + 1 min GPU
python3 -m src_int8.longctx.report lc_8k.npz --md      # section 1 table (golden / fake-quant / float)
python3 -m src_int8.longctx.decay --hist lc_8k.npz     # section 2 tables, usage shares from the run's p histogram
src_int8/demo/run_long.sh val.bin --full                # section 3: Verilator build + 2,048 / 8,192 forced and 1,200 closed-loop RTL runs (~35 min)
python3 -m src_int8.demo.host.long_run src_int8/demo/build/verilator/tb_mq_demo <out> --tokens 8192 --text-bin val.bin --offset 12000432
```

The .npz holds per-position NLL for the three models and per-step state statistics (25 MB) and is
not kept in the repository.
