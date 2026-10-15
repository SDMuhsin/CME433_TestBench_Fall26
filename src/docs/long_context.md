# Long contexts and the SSM decay near 1

Status: 2026-10-14. Open risk from `spec.md` section 9: "FP16 dA has ulp 2^-11 just below 1, contexts > 1k bytes not characterised". **Result: no fix needed, and the RTL is unchanged.** Over 8k and 32k bytes with the state carried, the golden arithmetic stays within +0.065 % BPB of float. Replacing the coarse dA by exact 2^p changes BPB by at most 0.004 %. The RTL matches golden bit for bit over 2,048 + 8,192 forced-input tokens and 1,200 closed-loop tokens, all without a state reset.

## 1. Decay path accuracy (`src/longctx/decay.py`)

Hardware: p = FP16(dt * A'), dA = exp2(p) = wb(T[i](1-f) + T[i+1]f, s), with 32 segments of 2^(j/32), an 11-bit truncated fraction and an FP16 output. Below 1, dA has ulp 2^-11. The script checks every negative FP16 p exhaustively against exact 2^p. tau = -1/ln(dA) is the state time constant in tokens. "Usage" is the share of the 1.6 G (token, channel, n) decay evaluations in the 8k run below.

| true tau [tokens] | max rel err dA | max rel err (1 - dA) = 1/tau | mean rel err (1 - dA) | usage |
|---|---|---|---|---|
| < 1 | 8.0e-4 | 3.6e-4 | -0.0 % | 14.9 % |
| 1-10 | 8.0e-4 | 3.6e-3 | -0.0 % | 41.1 % |
| 10-100 | 3.9e-4 | 2.7e-2 | +0.03 % | 27.9 % |
| 100-1000 | 2.8e-4 | 0.20 | -0.9 % | 13.2 % |
| 1000-10000 | 2.5e-4 | 1.0 (frozen) | -25 % | 2.7 % |
| > 10000 | 1.0e-4 | 1.0 (frozen) | -100 % | 6e-8 |

The remaining ~1 % have p < -13, where dA flushes to 0; that is correct, since 2^p < 1.2e-4.

- **dA itself is accurate.** The worst relative error is 8.0e-4, against 4.8e-4 for ideal FP16 rounding. Near 1 it is at most 2.5e-4, which is half an ulp, so it is ideal rounding there.
- **The decay rate 1 - dA is coarse for slow channels.**
  - tau <= 100: within 2.7 %.
  - tau 100-1000: quantised to multiples of 2^-11, so up to 20 % off.
  - tau ~2,000-4,100: all map to dA = 1 - 2^-11, i.e. an effective tau of about 2,000.
  - |p| <= 3.51e-4 (tau >= 4,110): dA rounds to 1, so the channel never decays. This applies to 0.34 % of decay evaluations.
- **The FP16 state does not stall the decay on its own.** With no input, h <- wb(dA*h) reaches 1/e as follows (median over 97 start values):

  | tau | tokens to 1/e |
  |---|---|
  | 100 | 103 |
  | 300 | 290 |
  | 1000 | 1,104 |
  | 2000-3000 | 1,480 |
  | 5000 | never (dA = 1) |

## 2. BPB by position, state carried (`src/longctx/long_eval.py`, `report.py`)

Setup:
- **Crops.** Random contiguous crops of the TinyStories V2 validation bytes. The stories are joined by EOS, so the state runs across story boundaries. There is no reset inside a crop.
- **Golden.** `ProbedHwModel` is asserted bit-exact with `HwModel`.
- **Float.** A float64 recurrent model built from the same checkpoint (`float_ref.py`). It agrees with the PyTorch float32 model to 2e-7 BPB at 8k.
- **Delta.** The paired golden minus float BPB on the same crops, with a 95 % CI over crops.

256 crops x 8,192 bytes (2.1 M predictions): overall golden 1.3603, float 1.3596 (+0.051 %).

| positions | golden BPB | float BPB | delta | rel | max abs h (hw / float) | saturated h | rel. state error |
|---|---|---|---|---|---|---|---|
| 0-256 | 1.3736 | 1.3734 | +0.0001 +- 0.0001 | +0.010 % | 17.1 / 17.1 | 0 | 0.40 % |
| 256-512 | 1.3455 | 1.3453 | +0.0001 +- 0.0002 | +0.010 % | 16.7 / 16.7 | 0 | 0.62 % |
| 512-1k | 1.3509 | 1.3506 | +0.0003 +- 0.0002 | +0.022 % | 17.3 / 17.3 | 0 | 0.83 % |
| 1k-2k | 1.3435 | 1.3431 | +0.0004 +- 0.0002 | +0.030 % | 19.1 / 19.1 | 0 | 1.08 % |
| 2k-4k | 1.3709 | 1.3701 | +0.0008 +- 0.0002 | +0.057 % | 19.0 / 19.0 | 0 | 1.30 % |
| 4k-8k | 1.3604 | 1.3596 | +0.0008 +- 0.0001 | +0.062 % | 19.3 / 19.3 | 0 | 1.44 % |

64 crops x 32,768 bytes (2.1 M predictions, other crops): overall +0.059 %. Per bucket:

| positions | delta |
|---|---|
| 0-1k | +0.016 to +0.018 % |
| 1k-8k | +0.046 to +0.055 % |
| 8k-16k | +0.064 % |
| 16k-32k | +0.062 % |

Max abs h is 26.6 (hw) against 26.6 (float), with 0 saturations.

The state error is ||h_hw - h_float|| / ||h_float||, averaged per bucket. It levels off rather than drifting:
- Block 0 settles at 0.43 % from about 1k on.
- Block 1 rises from 1.8 % (first 4k) to 2.6 % (8k-32k), then stays flat.

The BPB delta also stops growing after about 2k bytes, at +0.06 %. That is 8x below the 0.5 % threshold.

**Attribution ablation** (`--decay float`, 128 of the same 8k crops). The state update uses exact float 2^p instead of the FP16 LUT dA; everything else is unchanged (`lc_8k_floatdecay.md`). Its delta to float is the same: +0.014 % at 0-256, +0.063 % at 4k-8k.

Hardware dA minus exact dA, paired:

| positions | delta |
|---|---|
| 0-256 | +0.00001 +- 0.00005 bits |
| 512-2k | -0.00002 to +0.00002 bits |
| 2k-8k | +0.00005 +- 0.00003 bits (0.004 %) |

So the coarse decay accounts for essentially none of the long-context gap. The small residual (+0.06 %) comes from FP16 activations and state in general. Neither a finer exp2 segment nor an expm1-style formulation would remove it. Both would also leave the 2^-11 resolution of the FP16 state as the floor.

## 3. RTL == golden over long contexts (`src/demo/host/long_run.py`)

The RTL ran in Verilator: the full `mb_chip` from `rtl/chip.f`, the pad-level QSPI host `tb_mb_demo.sv` and the SRAM model, built by `src/demo/tb/build_verilator.sh`. That takes 0.35-0.75 s per token, against ~14 s in iverilog. Every run shows the same 801,056 clk START->done as iverilog.

Each run issues one STATE_RESET at token 0 and then carries the state. Every token's 128 logits are compared with `HwModel`.

| Run | Tokens | EOS crossed | Logits bit-exact | TB errors | max abs h |
|---|---|---|---|---|---|
| Forced input, val.bin[5000379:+2048] | 2,048 | 3 | 2,048 x 128 | 0 | 11.9 |
| Forced input, val.bin[12000432:+8192] | 8,192 | 10 | 8,192 x 128 | 0 | 16.5 |
| Closed loop, "Once upon a time", T = 0.8, seed 0, sampling from the chip's logits | 1,200 | 1 | 1,200 x 128 | 0 | 7.4 |

## Reproduce (repo root; val.bin from `python3 -m src.model.data`, checkpoint from `src.model.train`)

```
python3 -m src.longctx.long_eval src/golden/params/mamba_e96_fp16.npz e96.pt val.bin lc_8k.npz --n 256 --length 8192   # ~25 min
python3 -m src.longctx.long_eval ... lc_8k_floatdecay.npz --n 128 --length 8192 --decay float                          # ablation
python3 -m src.longctx.long_eval ... lc_32k.npz --n 64 --length 32768 --seed 777                                       # ~15 min
python3 -m src.longctx.report lc_8k.npz [--md]          # bucket table
python3 -m src.longctx.decay --hist lc_8k.npz           # section 1 table
src/demo/run_long.sh val.bin [tokens] [offset]          # Verilator build + forced (2048) and closed-loop (1200) RTL runs
python3 -m src.demo.host.long_run src/demo/build/verilator/tb_mb_demo <out> --tokens 8192 --text-bin val.bin --offset 12000432
```

The text outputs are in `src/longctx/results/`: `decay.txt`, `lc_8k.md`, `lc_8k_floatdecay.md` and `lc_32k.md`. The raw .npz files hold per-position NLL (10-40 MB) and are not kept. The RTL runs write `long.json` and `host.log` to `src/demo/build/long_*` (git-ignored).
