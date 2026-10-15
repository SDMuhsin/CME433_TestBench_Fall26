# Mamba byte-LM ASIC: model and hardware arithmetic contract

Status: `mb_chip` is hardened and signed off (`signoff.md`, `results.md`); the RTL and the routed netlist are bit-exact against this spec's golden model (`arch.md`, `verification.md`). Base silicon: the signed-off `dla_fp16_chip`
(FP16xFP16->FP32 MAC lane, quad-SPI weight stream, 256x8 `gf180mcu_ocd_ip_sram` macros,
die 1675 x 1110 um, 40 ns clock). This document is normative; `src/golden/` implements it
bit for bit and is the reference for RTL.

## 1. Model

| Item | Value |
|---|---|
| Data | TinyStories V2 (GPT-4), byte level |
| Vocab | 128 (7-bit ASCII). Typographic quotes/dashes/ellipsis map to ASCII; other non-ASCII and control chars except `\n` are dropped; byte `0x00` = end of story (EOS) |
| Embedding | tied: logits = RMSNorm_f(x) . E^T |
| Blocks | 2 x pre-RMSNorm Mamba mixer + residual, then final RMSNorm |
| d_model / d_inner / N / conv / dt_rank | 64 / **96** / 4 / 2 / 4 |
| Params | 50,048 (float), 49,920 FP16 words streamed per token |
| RMSNorm | x * rsqrt(mean(x^2) + 2^-12) * g |

Block (per token, x in R^64):

```
xn      = RMSNorm(x) (gain g)
[xi; z] = W_in xn                         W_in [2E, 64], no bias
u       = SiLU(cb + w0 * xi_prev + w1 * xi)  depthwise causal conv, width 2
[dl; B; C] = W_x u                        W_x [R + 2N, E], no bias
dt      = softplus(b_dt + W_dt dl)        W_dt [E, R]
h[d,n]  = exp(dt[d] A[d,n]) h[d,n] + dt[d] B[n] u[d]       A = -exp(A_log)
y[d]    = sum_n C[n] h[d,n] + D[d] u[d]
x       = x + W_out (y * SiLU(z))         W_out [64, E], no bias
```

Training: `src/model/` (AdamW 3e-3, warmup 500 + cosine, 20k steps x 64 x 512 bytes = 655 M
bytes, float32; ~20 min on one A40).

## 2. Configuration decision

Both widths were trained identically (seed 0). BPB on 256 fixed validation crops of 1024
bytes (262k predictions, zero state per crop):

| d_inner | Params | Float BPB | Golden-HW BPB | Delta | State B | Act B | Total SRAM B | 256x8 macros | Words/token | ms/token @ 25 MHz |
|---|---|---|---|---|---|---|---|---|---|---|
| 64 | 36,160 | 1.4604 | 1.4604 | +0.00% | 1,280 | 424 | 1,704 | 8 | 36,032 | 23.1 |
| **96** | **50,048** | **1.3546** | **1.3549** | **+0.02%** | **1,920** | **488** | **2,408** | **10** | **49,920** | **32.0** |

FP16 words occupy a hi/lo macro pair (256 words per pair), so macros come in pairs.
`config_fp16.yaml` places 8 macros (2 rows x 4, y = 297.6-802.4 um; core 40-1070 um, 44 %
utilisation). Ms/token assumes the stream is the bottleneck, at the FP16 chip's measured rate
of 0.642 us per 16-bit word.

**Decision: d_inner = 96.**
- It is 7.2 % better in BPB, the clearest quality step available at this size.
- The cost is one more macro pair: 2 x 0.068 = 0.136 mm^2, 7 % of the 1.86 mm^2 die. The pair fits in a third macro row above y = 802 um, which has about 268 um of free core height.
- d_inner = 64 is the fallback: it fits the existing 8-macro floorplan unchanged.

## 3. Number format and the MAC lane

- **Storage.** IEEE binary16 bit patterns everywhere: weights, activations, state and logits. Values are canonical:
  - no subnormals (FTZ to +0);
  - no Inf/NaN (saturate to +-65504);
  - never -0.

  The host exporter produces canonical words (`fp.to_fp16`: float64 -> RNE -> FTZ / saturate).
- **Lane step:** `acc = RNE32(acc + a*b)`.
  - The FP16 x FP16 product is exact in FP32 (11 x 11 bits, |p| in [2^-28, 2^32]).
  - Exactly one FP32 rounding per step. No FMA, no FP32 subnormals or Inf are possible.
  - Exact cancellation gives +0.
- **Dot.** `acc` starts at +0, or at an FP16 *init* operand (bias / residual / constant, converted exactly).
  - Then one lane step per pair, in the listed order.
  - Every dot/GEMV below lists init first, then k = 0, 1, 2, ...
- **Writeback** `wb(acc, s)`. `s` is a signed integer from the sequencer; 0 unless stated.
  - `v = acc * 2^s` (exact exponent add).
  - `|v| < 2^-14` -> +0.
  - Otherwise RNE to FP16; a magnitude above 65504 saturates to +-65504.
- **Notation.** `mul(a, b) = wb(a*b)` (single rounding). `gemv(W, x, init)[o] = wb(init[o] + sum_k W[o,k] x[k])`.

## 4. Shared nonlinear unit (one ROM + linear interpolation on the lane)

The unit computes three things from the FP16 input x:
- a ROM index i;
- a fraction f = q / 2^11 with integer q in [0, 2^11];
- an output scale s.

It then runs two lane steps:

`out = wb( T[i] * (1 - f) + T[i+1] * f , s )`

f and 1 - f are exact FP16 values. All address arithmetic is exact (fixed point; FP16 inputs have at most 24 fraction bits). Fractions are truncated: `q = floor(frac * 2^11)`.

| Function | Mode | Grid | Segments | ROM words | Address / scale | Out of range |
|---|---|---|---|---|---|---|
| sigmoid | uniform | [-8, 8], step 1/8 | 128 | 0-128 | u = (clamp(x) + 8) * 8 | clamp: x >= 8 gives T[128], x <= -8 gives T[0] |
| softplus | uniform | [-8, 8], step 1/8 | 128 | 129-257 | same as sigmoid | x >= 8: out = x (bypass); x < -8 gives T[0] |
| exp2 | exp2 | 2^(j/32) | 32 | 258-290 | p = min(x, 0), s = floor(p), u = (p - s) * 32 | s pushes small results to FTZ |
| rsqrt | rsqrt | m in [1, 4], step 1/16 | 48 | 291-339 | x = m 2^e, m in [1, 4), e even; u = (m - 1) * 16, s = -e/2 | input is always > 0 |

Common rules:
- Segment index: i = min(floor(u), segments - 1). So u = segments gives f = 1.
- ROM contents: T = FP16 RNE of the float64 function at each grid point.
- Total ROM: **340 x 16 b = 5,440 bits (680 B)**.

Accuracy, measured exhaustively over all legal FP16 inputs (`tests/test_nlu.py`):

| Function | Range | Max error |
|---|---|---|
| sigmoid | [-8, 8] | 5.8e-4 abs (about 1.2 ulp) |
| softplus | [-8, 8] | 0.27 % rel |
| exp2 | (-13, 0] | 8.0e-4 rel |
| rsqrt | all inputs | 8.8e-4 rel |

Derived functions:
- `SiLU(x) = mul(x, sigmoid(x))`.
- exp is never needed: the host streams A' = A * log2(e), so dA = exp2(dt * A').

## 5. Per-token operation sequence (normative)

Notation: indices d < E, n < N, i < 64. All results are FP16 unless named `acc`.

1. **Embedding.** x = E_in[token] (64 words from the stream).
2. **For each block.** The norm gain g is folded into W_in by the exporter.
   - RMSNorm:
     - acc = 2^-6 + sum_i x_i * x_i
     - ms = wb(acc, -6)
     - r = rsqrt(ms)
     - xn_i = mul(x_i, r)

     The effective eps is 2^-12.
   - In_x + conv, per d:
     - xi = wb(sum_k W_in_x[d,k] xn_k)
     - xc = wb(cb[d] + w0[d]*CONV[d] + w1[d]*xi)
     - CONV[d] = xi
     - U[d] = SiLU(xc)
   - x_proj, per j < 12: DBC[j] = wb(sum_k W_x[j,k] U[k]). Here dl = DBC[0..3], B = DBC[4..7], C = DBC[8..11].
   - Channel, per d:
     - dt = softplus(wb(b_dt[d] + sum_r W_dt[d,r] dl[r]))
     - z = wb(sum_k W_in_z[d,k] xn_k)
     - dtu = mul(dt, U[d])
     - per n:
       - dA = exp2(mul(dt, A'[d,n]))
       - H[d,n] = wb(dA*H[d,n] + dtu*B[n])
     - y = wb(C[0]H[d,0] + ... + C[3]H[d,3] + D[d]*U[d])
     - U[d] = mul(y, SiLU(z))
   - Out, per i: X[i] = wb(X[i] + sum_d W_out[i,d] U[d]). The residual is the accumulator init.
3. **Logits.** Final RMSNorm (same sequence as in step 2), then logit[v] = wb(sum_k E_out[v,k] xn_k) for v < 128. The exporter folds the final gain into E_out = E * g_f.

Order between channels/rows is free. Only each scalar's op sequence above is normative.

Per token, the lane executes about 7.5k operations beyond the 49,920 streamed MACs (norms, conv, scan, LUT interpolation). These are hidden under the 16-clock-per-word stream.

## 6. On-chip memory map (d_inner = 96)

The memory holds FP16 words. Each word address maps to one hi/lo macro pair.

| Region | Word base | Words | Bytes | Contents |
|---|---|---|---|---|
| H0 | 0x000 | 384 | 768 | SSM state, block 0, [d][n] |
| H1 | 0x180 | 384 | 768 | SSM state, block 1 |
| CONV0 | 0x300 | 96 | 192 | conv state (previous xi), block 0 |
| CONV1 | 0x360 | 96 | 192 | conv state, block 1 |
| XN | 0x3C0 | 64 | 128 | normalised activations |
| X | 0x400 | 64 | 128 | residual stream |
| U | 0x440 | 96 | 192 | u, then the gated output, in place |
| DBC | 0x4A0 | 12 | 24 | dt_low, B, C |
| TMP | 0x4AC | 8 | 16 | spare (the RTL keeps scalars in sequencer registers R0..R4) |
| LOGITS | 0x400 (alias X+U) | 128 | 256 | read back by host |

- Totals: 1,204 words = 2,408 B. Of that, 1,920 B is persistent state and 488 B is activations.
- Storage: 5 macro pairs (10 macros), 1,280 words.
- State reset (new sequence): the host writes CTRL.STATE_RESET; the microcode zeroes H* and CONV* (also required once after power-up).
- Source of truth: `src/golden/data/memmap.py`.

## 7. Host protocol

- **Stream format.** Per token, the host sends 49,920 FP16 words, MSB byte first, as in the FP16 chip. Source of truth: `src/golden/data/stream.py`.

  ```
  EMB     E_in[token, 0..63]
  per block:
    IN_X    for d < E:   W_in_x[d, 0..63], cb[d], w0[d], w1[d]
    X_PROJ  for j < 12:  W_x[j, 0..E-1]
    CHAN    for d < E:   b_dt[d], W_dt[d, 0..3], A'[d, 0..3], D[d], W_in_z[d, 0..63]
    OUT     for i < 64:  W_out[i, 0..E-1]
  LOGITS  for v < 128:   E_out[v, 0..63]
  ```

- **Token step.** `START` (0x31), then `STREAM_Q` (0x32) of the stream, with HRDY checked before every byte. HRDY high again means the step is done.
- **Readback.** After the stream, the host reads the 128 FP16 logits (256 B) with `RD_MEM_Q` (0x6B) at memory byte address 0x800. The byte address is 2 x word + (0 = high byte, 1 = low byte).
- **Sampling.** The host samples in float64, either greedy or softmax(logit / T) with a seeded RNG (`src/golden/host/sampler.py`). The sampled byte is the next token. EOS (0x00) ends a story.

### 7.1 Abort and reset (normative)

Definitions:
- A *run* is a token step (START) or the state-reset routine (STATE_RESET).
- The *state* is H0, H1, CONV0 and CONV1, memory words 0x000-0x3BF.
- The *logits* are memory bytes 0x800-0x8FF.
- STATUS.done = 1 means the last requested run completed. Every START or STATE_RESET request clears it, the run's END sets it, and `rst_n` clears it.
- "Kept" means bit-identical to the value before the abort. "Undefined" means the host must not rely on it.

| Host action | Effect | STATUS / CSRs after | State | Logits |
|---|---|---|---|---|
| `rst_n` low, at any time | All flops reset asynchronously. The IO drivers turn off at once; HRDY is high during reset | Reset values: CTRL 0x04, STATUS 0x04, byte count 0 | Undefined, as at power-up | Undefined |
| CTRL.soft_reset = 1 (write 0x05) | Stops the run in the cycle the write lands. The stream FIFO is emptied and lane steps in flight are dropped. Held while the bit is 1 | busy 0, tok 0, hrdy 1, err_ovf 0, byte count 0; done unchanged | Idle: kept. Token step: kept if fewer than **262** stream bytes were accepted, else undefined. State reset: undefined | Idle: kept. Token step: undefined |
| START or STATE_RESET while soft_reset is held, including a single CTRL write of 0x07 | Not executed: no memory, stream or datapath activity | done 0, err_cmd 0 | Kept | Kept |
| STREAM_Q bytes while soft_reset is held, or while idle | Dropped, with no err_ovf | Byte count unchanged (0 while held) | Kept | Kept |
| STATE_RESET while busy | The current run is abandoned and the reset routine starts | After HRDY: done 1 | Zero | Not written by the routine; an interrupted token step leaves them undefined |
| START while busy | The current run is abandoned and a token step restarts from stream byte 0. The host sends that token's whole stream | busy 1, tok 1, byte count 0 | Interrupted token step: as for soft_reset. Interrupted state reset: undefined | Undefined |
| CS_N high mid-frame | The frame ends. Only completed bytes count: a command byte without its 8th bit does nothing (no err_cmd), a WR_CSR without a complete data byte writes nothing, and a partial STREAM_Q byte is dropped. The host resumes the stream at the byte count (CSR 0x03-0x05) | Unchanged | Kept | Kept |
| RD_MEM[_Q] / RD_CSR while busy | No effect on the run. RD_MEM data is undefined while busy | Unchanged | Kept | Kept |
| Stream overrun (a byte arrives while the FIFO is full, i.e. HRDY ignored) | The byte is dropped, so the token is corrupt | err_ovf 1 (sticky until START, STATE_RESET or soft_reset) | Undefined | Undefined |

**Recovery.**
- **State undefined.** Write STATE_RESET and wait for HRDY before the next START. The next tokens then match golden from zero state.
- **State kept.** Re-send the aborted token: START plus its full stream. The result matches golden continuing from the last completed token.
- **Releasing soft_reset.** Write CTRL = 0x04 (keep quad_en).

**Host timing.**
- `rst_n` may be asserted asynchronously. Deassert it synchronously to clk: it is timed as an input with the IO delay.
- Hold CS_N high during reset, and keep it high for >= 2 clk after release and between frames.
- After any abort, the next frame must start with CS_N high.

The 262-byte window is the first state write of a token step, `CONV0[0]`. That write needs stream word 130 (`w1[0]`), so a step that has received fewer bytes has not touched the state. `src/ucode/tests/test_abort_rules.py` derives the 262 from the microcode.

A START or STATE_RESET that meets a held soft reset still runs P0 of its entry uop for one cycle. Both entries begin with a LOOP uop, which has no side effect in P0; the same test asserts this.

Loop counters, NLU and register-file contents are not reset by an abort. Every run writes them before reading them.

## 8. Golden model and collateral

`src/golden/`:

| File | Contents |
|---|---|
| `arith/fp.py` | lane, writeback |
| `arith/nlu.py` | ROM + LUT unit |
| `net/layers.py` | norm, conv, scan, block |
| `net/model.py` | recurrent token step; also `step_stream`, which consumes the raw word stream |
| `data/weights.py` | checkpoint -> folded FP16 `.npz` |
| `data/stream.py` | stream order |
| `data/memmap.py` | memory map |
| `host/sampler.py`, `host/generate.py` | host sampling and generation |
| `host/evaluate.py` | golden BPB |
| `host/vectors.py` | stories -> chip TB vectors (`plan.memh` with state-reset flags, `stream.memh`, `logits.memh`) |
| `params/mamba_e96_fp16.npz` | the shipped FP16 weights |

Tests: `python3 -m pytest src/golden/tests src/ucode/tests` (the latter checks the microcode against this golden).

Reproduce:

```
python3 -m src.model.data TinyStoriesV2-GPT4-train.txt train.bin   # same for valid
python3 -m src.model.train --train-bin train.bin --val-bin val.bin --out e96.pt --d-inner 96
python3 -m src.golden.data.weights e96.pt e96_fp16.npz
python3 -m src.model.evaluate e96.pt val.bin ; python3 -m src.golden.host.evaluate e96_fp16.npz val.bin
python3 -m src.golden.host.generate e96_fp16.npz --prompt "Once upon a time" --temperature 0.8 --seed 0
```

## 9. Open risks

- **Abort / reset paths (closed 2026-10-14, `verification.md`).** Every host abort in section 7.1 was injected at directed, triggered and random points of a token step, the state reset, the readback and the QSPI frames. After each one, `src/tb/run_abort.sh` checks the idle FSMs, STATUS, and the state and next tokens bit-exact against golden. The iverilog run adds the X checks. The tests found no RTL bug, and the RTL is unchanged.

- **Coarse decay values (closed 2026-10-14, `long_context.md`).** FP16 dA has ulp 2^-11 just below 1, so slow channels are quantised. Time constants of 100-1000 tokens are off by up to 20 %, and tau >= 4,110 tokens freezes at dA = 1 (0.34 % of decay evaluations). This is measured harmless: with the state carried over 8k and 32k bytes, golden stays within +0.065 % BPB of float in every position bucket. The gap plateaus after about 2k bytes, and exact 2^p would recover only 0.004 % of it. RTL == golden is shown over 8,192 tokens without a reset.
- **sum x^2 range.** RMSNorm's sum x^2 saturates if rms(x) exceeds about 256. It is not observed: over 64 x 1k validation crops the largest pre-rounding value was 664, with 0 saturations. Nothing guards against it in hardware.
- **Floorplan (closed 2026-10-13, `signoff.md`).** The 10-macro floorplan (a third macro row) is placed, routed and signed off: 0 DRC/LVS errors, worst setup +18.35 ns and worst hold +0.104 ns over 9 corners, SDF-annotated GLS clean at min/nom/max.
- **Text quality.** It is limited at 50k parameters: it is locally fluent but semantically loose.
