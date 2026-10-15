# Mamba byte-LM ASIC, INT8 edition (`mq_chip`): numerics and arithmetic contract

Status: revision 1 (2026-10-14): QAT, export and the integer golden exist and implement this
document bit for bit; RTL to do. This document is normative. Changelog at the end.
`src_int8/golden/` will implement it bit for bit and is the reference for the RTL. The chip is
the INT8 twin of `src/` (`mq_chip`, FP16): same model, same host protocol except where section 8
says otherwise, same silicon template (A56/ACV block, 1675 x 1110 um, GF180MCU, 40 ns clock,
`gf180mcu_ocd_ip_sram__sram256x8m8wm1` macros).

Everything below is decided. The one table that the other teams must share is section 3
(formats); it is to be coded once, in `src_int8/golden/formats.py`, and imported by the golden
model, the exporter, the QAT fake-quant, the microcode and the vector generators.

## 1. Model (unchanged from FP16)

| Item | Value |
|---|---|
| Data | TinyStories V2 (GPT-4), byte level, vocab 128, byte 0x00 = EOS; same byte mapping as `src/model/data.py` |
| Architecture | tied embedding, 2 x (pre-RMSNorm Mamba mixer + residual), final RMSNorm, logits = RMSNorm_f(x) . E^T |
| d_model / d_inner / N / conv / dt_rank | 64 / 96 / 4 / 2 / 4 |
| RMSNorm | x * rsqrt(mean(x^2) + 2^-12) * g; both gains are folded into the following weights by the exporter |
| Float params | 50,048 |

Block, per token (x in R^64), as in `src/docs/spec.md` section 1:

```
xn      = RMSNorm(x)
[xi; z] = W_in xn
u       = SiLU(cb + w0 * xi_prev + w1 * xi)
[dl; B; C] = W_x u
dt      = min(softplus(b_dt + W_dt dl), 8)                 <- clamp is new (section 3)
h[d,n]  = exp2(dt[d] A'[d,n]) h[d,n] + dt[d] B[n] u[d]     A' = -exp(A_log) * log2(e)
y[d]    = sum_n C[n] h[d,n] + D[d] u[d]
x       = x + W_out (y * SiLU(z))
```

Training is quantisation-aware (section 9). The float reference for the BPB target is the FP16
chip's golden figure, 1.3549 BPB on the 256 x 1024-byte validation crops of `src_int8/golden/evaluate.py`.

## 2. Arithmetic style and why

Choices, with the reasons they were made:

- **Weights INT8, symmetric, one scale per output row** (per channel). Requantisation is an
  **INT32 x UINT16 multiplier plus shift** per row, streamed with the row. Power-of-two
  per-tensor scales were rejected: the dt projection, the A' decay constants and `b_dt` vary by
  more than 100x between channels, and the model has only 50k parameters, so per-row scales are
  where the INT8 accuracy comes from. A 16-bit multiplier (2^-14 relative precision) is far
  below the INT8 output resolution; a 32-bit multiplier would buy nothing. The cost is 3 bytes
  per row, 3,144 bytes per token (5.8 % of the stream).
- **Activations INT8 with fixed power-of-two scales** (section 3), so every element-wise product
  is a shift. The scales are fixed in this document from measured ranges of the FP16 model and
  are also the clipping ranges the QAT trains against. Three activations are INT16 because INT8
  cannot hold them: the residual stream (its range grows to +-47 while block 0 sees +-3), and the
  LUT inputs `xc`, `z`, `dt_pre` (the sigmoid/softplus tables need 1/256 input steps).
- **Accumulator INT32**, no saturation, with a per-MAC product shift `ps` so that terms of
  different units can be summed in one accumulation. Section 5 proves that no accumulation can
  overflow; the golden asserts it.
- **SSM state INT24, Q6.17.** INT16 was rejected by the dead-band argument: a decay step
  `h <- round(dA h)` stalls once `(1 - dA) |h| < 0.5 LSB`; for a time constant of 1,000 tokens an
  INT16 Q3.12 state would stall below |h| = 0.12, which is the typical state magnitude (rms 0.19).
  Q6.17 moves the stall to 0.004 (1 % of the equilibrium value of such a channel). The memory
  cost is 9 SRAM macros for the state (section 6).
- **Decay factor dA UINT16 Q0.15** from an exp2 LUT, saturating at 1 - 2^-15. Channels freeze
  (dA = 1) only for tau > 45,000 tokens, against 4,110 in FP16.
- **One shared LUT unit** (sigmoid, softplus, exp2, rsqrt): 340 x 16-bit ROM, linear
  interpolation executed as two lane MACs, as in the FP16 chip.
- **Rounding everywhere: round half up**, `rsh(v, k) = (v + 2^(k-1)) >> k` (arithmetic shift),
  `rsh(v, 0) = v`. Ties go towards +inf. This is the one rounding primitive of the chip.
- **Saturation** `sat_w(v)`: clamp to the signed w-bit range, w in {8, 16, 24}.
- **Byte order: little endian** for every multi-byte item in the stream, the memory and the
  host read-back (the FP16 chip was MSB first).

## 3. Formats (normative table; `golden/formats.py`)

Fixed point notation: `Qm.f` is a signed two's-complement integer with f fraction bits
(value = int / 2^f), m integer bits, total width m + f + 1. "INT8 s=2^-k" means an INT8 whose
value is int * 2^-k, range [-128, 127] * 2^-k.

### 3.1 Activations and state

| Tensor | Where | Format | Value LSB | Range | Basis (FP16 model: absmax / rms) |
|---|---|---|---|---|---|
| X (residual), E_in row | BMEM INT16 | Q7.8 | 2^-8 | +-128 | 47 / 1.9 (final), 3.2 / 0.36 (block 0) |
| XN (normalised) | BMEM INT8 | s = 2^-5 | 1/32 | +-3.97 | 4.5 / 1.0 |
| XI (conv input; CONV state) | BMEM INT8 | s = 2^-4 | 1/16 | +-7.94 | 8.6 / 1.6 |
| XC (conv output, SiLU input) | register INT16 | Q7.8 | 2^-8 | +-128 | 7.3 / 0.95 |
| U (u = SiLU(xc)) | BMEM INT8 | s = 2^-4 | 1/16 | +-7.94 | 6.8 / 0.5 |
| DL (dt_low) | BMEM INT8 | s = 2^-3 | 1/8 | +-15.9 | 9.9 / 2.0 |
| B | BMEM INT8 | s = 2^-5 | 1/32 | +-3.97 | 4.4 / 0.68 |
| C | BMEM INT8 | s = 2^-4 | 1/16 | +-7.94 | 6.2 / 0.9 |
| DT_PRE (softplus input) | register INT16 | Q7.8 | 2^-8 | +-128 | 24 / 4.4 |
| DT (softplus output) | register INT16 | Q3.12, >= 0 | 2^-12 | [0, 8) | 9.75 / 0.48 (clamped at 8) |
| BU (B[n] u) | register INT16 | s = 2^-9 | 2^-9 | exact product | - |
| P (dt A') | lane acc INT32 | Q11.19 | 2^-19 | +-2048 | -603..0 |
| DA (exp2 P) | register UINT16 | Q0.15, >= 0 | 2^-15 | [0, 1) | - |
| H (SSM state) | HMEM INT24 | Q6.17 | 2^-17 | +-64 | 17.8 / 0.19 |
| Y (scan output) | register INT16 | Q6.9 | 2^-9 | +-64 | 31.8 / 0.64 |
| Z (gate input) | register INT16 | Q7.8 | 2^-8 | +-128 | 10.5 / 1.4 |
| SIG (sigmoid output) | register UINT16 | Q0.15 | 2^-15 | [0, 1) | - |
| SZ (SiLU(z)) | register INT16 | Q7.8 | 2^-8 | +-128 | - |
| G (y SiLU(z), out_proj input) | BMEM INT8 (in U) | s = 2^-4 | 1/16 | +-7.94 | 26.5 / 0.51 (clipped) |
| MS (mean square + eps) | lane acc UINT32 | Q.16 | 2^-16 | [2^-12, 2^14) | sum x^2 <= 95 |
| R (rsqrt output) | register INT16 | Q6.9, > 0 | 2^-9 | (0, 64] | - |
| LOGITS | BMEM INT16 | Q7.8 | 2^-8 | +-128 | 27.6 / 7.7 |

The QAT clips every tensor to exactly these ranges (section 9). G and U share the U region of
the memory, at different times, with different scales.

### 3.2 Streamed parameters

| Item | Format | Notes |
|---|---|---|
| W_in_x, W_in_z, W_x, W_dt, W_out, E_out | INT8, per-row symmetric | `w = clamp(round(w_f / s_row), -127, 127)`, `s_row = max_k |w_f[row, k]| / 127` (a row of zeros gets s_row = 1) |
| conv w0, w1 | INT8, one scale per channel d shared by w0 and w1 | `s_c[d] = max(|w0[d]|, |w1[d]|) / 127` |
| D | INT8, s = 2^-6 | range [0.1, 1.7] in the FP16 model |
| A' | INT16 Q8.7 | clamp to [-256, -2^-7]. Values below -256 only occur with dt A' < -16, where dA = 0 anyway |
| cb, b_dt | INT16 Q7.8 | added after requantisation, in the destination format (XC / DT_PRE) |
| E_in row | INT16 Q7.8 | the input side of the tied embedding, quantised separately from E_out |
| requant pair (M, s) | UINT16 M in [2^14, 2^15), UINT8 s in [1, 47] (bits 7:6 zero) | one per weight row, see 3.3 |

### 3.3 Requantisation constants

For a row with weight scale `s_w`, input activation scale `s_in` (power of two) and output
format LSB `s_out` (power of two), the exporter computes the exact ratio
`r = s_w * s_in / s_out` in float64 and encodes it as `M / 2^s`:

```
s = 14 - floor(log2(r))            # so that r * 2^s is in [2^14, 2^15)
M = round(r * 2^s)
if M == 2^15: M = 2^14; s = s - 1  # rounding carried into the next octave
assert 1 <= s <= 47 and 2^14 <= M < 2^15
```

The conv row d uses `s_w = s_c[d]`, `s_in = 2^-4`, `s_out = 2^-8`. Rows and their (s_in, s_out):

| Rows | s_in | s_out | Output |
|---|---|---|---|
| W_in_x[d] | 2^-5 (XN) | 2^-4 | XI INT8 |
| conv[d] | 2^-4 (XI) | 2^-8 | XC INT16 (+ cb) |
| W_x[j], j < 4 | 2^-4 (U) | 2^-3 | DL INT8 |
| W_x[j], 4 <= j < 8 | 2^-4 | 2^-5 | B INT8 |
| W_x[j], 8 <= j < 12 | 2^-4 | 2^-4 | C INT8 |
| W_dt[d] | 2^-3 (DL) | 2^-8 | DT_PRE INT16 (+ b_dt) |
| W_in_z[d] | 2^-5 (XN) | 2^-8 | Z INT16 |
| W_out[i] | 2^-4 (G) | 2^-8 | X INT16 (+ X[i]) |
| E_out[v] | 2^-5 (XN) | 2^-8 | LOGITS INT16 |

## 4. The lane and the writeback (normative)

### 4.1 MAC lane

One accumulator `acc` (INT32). Operands: side **a** is a signed 24-bit value, side **b** a signed
16-bit value; narrower sources are sign-extended, the LUT ROM word (unsigned 16 bits) and the
LUT fraction are zero-extended. `ps` is a 4-bit per-step constant from the microcode.

```
step(a, b, ps):   acc <- base + rsh(a * b, ps)      base = init (first step) or acc
```

`a * b` is exact (40 bits). `init` is 0 or the constant 16 (the RMSNorm eps, section 5.2). The
accumulation never overflows INT32 for the operand ranges of section 5; the lane has no
saturation and the golden asserts `|acc| < 2^31` after every step.

### 4.2 Writeback

The writeback turns `acc` into a stored value. It has two scaling forms, an optional addend and
a width:

```
wb_sh(acc, sh)       = rsh(acc, sh)                            sh in 0..31, microcode immediate
wb_rq(acc, M, s)     = (acc * M + 2^(s-1)) >> s                 (M, s) from the RQ register
v    = wb_x(acc) + addend                                       addend = 0 or an INT16 register
out  = sat_w(v)                                                 w in {8, 16, 24}, or raw (w = 32, LUT input only)
```

`acc * M` is exact (48 bits); `v` is exact (the RTL needs 34 bits). The RQ register `{M, s}` is
loaded from the stream (3 bytes: M low, M high, s) before the rows that use it. `wb_sh` with
`sh = 0` and `w = 32` passes `acc` unchanged to the LUT unit (MS and P).

Notation used below: `rq_w(acc [, addend])` = `sat_w(wb_rq(acc, RQ) + addend)` and
`sh_w(acc, k)` = `sat_w(wb_sh(acc, k))`.

## 5. Shared nonlinear unit and per-token sequence (normative)

### 5.1 LUT unit

One ROM of 340 unsigned 16-bit words, four functions, linear interpolation on the lane:

```
Sigma = T[i] * (2^11 - f) + T[i+1] * f          two lane steps, ps = 0, init 0, f in 0..2^11
out   = sh_16(Sigma, sh_fn)                       sh_fn from the unit (table below)
```

| Function | ROM words | T[j] (exact integers) | Input and address arithmetic | sh_fn | Output |
|---|---|---|---|---|---|
| sigmoid | 0..128 | round(sigmoid(-8 + j/8) * 2^15), j = 0..128 | x: INT32 read as Q7.8; `x = clamp(x, -2048, 2048)`; `u = x + 2048`; `i = min(u >> 5, 127)`; `f = (u - 32 i) << 6` | 11 | SIG Q0.15 |
| softplus | 129..257 | min(round(softplus(-8 + j/8) * 2^12), 32767) | same as sigmoid | 11 | DT Q3.12 (T[128] = 32767, so x >= 8 saturates to 8 - 2^-12: no bypass) |
| exp2 | 258..290 | round(2^(j/32) * 2^14), j = 0..32 (T[32] = 32768) | p: INT32 read as Q11.19. `p >= 0 -> p = 0`. `p <= -16 * 2^19 -> out = 0` (zero flag, the lane result is discarded). Else `e = p >> 19` (floor, in -16..-1 or 0), `frac = p & (2^19 - 1)`, `i = frac >> 14`, `f = (frac >> 3) & 0x7FF` | 10 - e | DA Q0.15; p = 0 gives 2^15, saturated to 32767 |
| rsqrt | 291..339 | round(2^14 / sqrt(1 + j/16)), j = 0..48 | n: UINT32 read as Q.16, n >= 16. `b = floor(log2 n)` (4..30); `E = b - 16`, decremented by 1 if odd; `m16 = n >> E` for E >= 0 else `n << -E` (in [2^16, 2^18)); `u = m16 - 2^16`; `i = u >> 12` (0..47); `f = (u >> 1) & 0x7FF` | 16 + E/2 | R Q6.9 |

Fractions are truncated, never rounded. `f = 2^11` can occur only for sigmoid/softplus at
`u = 4096` (then `i = 127` and the result is exactly T[128]). SiLU(x) = `sh_16(x * SIG, 15)` for
Q7.8 x (two further uops: one MAC with ps = 0, one writeback). The input to sigmoid/softplus is
the INT32 writeback value; it is clamped inside the unit, so no 16-bit saturation precedes it.

Interpolation accuracy (exact arithmetic, checked over all 4,097 inputs of the uniform tables
and all 2^19 fractions of exp2 / 3 x 2^16 of rsqrt; the golden tests repeat this): sigmoid
<= 2.1e-4 abs (after rounding), softplus <= 6.5e-4 abs (2.7 LSB of Q3.12), exp2 <= 7.9e-5
relative before rounding (<= 4.7 LSB of Q0.15 mid-segment; near p -> 0, where slow channels
live, the error is below 1e-6 because the grid point 2^0 is exact), rsqrt <= 3.6e-4 relative.

### 5.2 Per-token sequence

Indices: d < 96, n < 4, i, k < 64, r < 4, v < 128. `S8/S16` = next stream byte / LE 16-bit word.
`RQ <- S` loads the requant pair. `mac(ps, a, b)` is one lane step. Every accumulation starts
with `acc = init` (0 unless given) and lists its steps in order. Only each scalar's op sequence
is normative; the order between channels or rows is free.

1. **Embedding.** `X[k] = S16` (INT16 Q7.8), 64 words.
2. **For each block l:**
   - **RMSNorm** (`x = X`):
     - `acc = 16; for i: mac(6, x[i], x[i])` (acc is mean(x^2) + 2^-12 in Q.16; <= 2^30)
     - `r = rsqrt(acc)` (LUT, input raw)
     - `XN[i] = sh_8(x[i] * r, 12)` for each i (one `mac(0)` each)
   - **in_x + conv**, per d (stream row: W_in_x[d, 0..63], RQ, w0, w1, RQ_conv, cb):
     - `acc = sum_k mac(0, S8, XN[k]); RQ <- S; xi = rq_8(acc)`
     - `acc = mac(0, S8 (w0), CONV_l[d]) + mac(0, S8 (w1), xi); RQ <- S; cb = S16; xc = rq_16(acc, cb)`
     - `CONV_l[d] = xi`
     - `sig = sigmoid(xc); U[d] = sh_8(xc * sig, 19)`
   - **x_proj**, per j < 12 (row: W_x[j, 0..95], RQ): `acc = sum_k mac(0, S8, U[k]); RQ <- S; DBC[j] = rq_8(acc)`.
     DL = DBC[0..3], B = DBC[4..7], C = DBC[8..11].
   - **channel**, per d (row: b_dt, W_dt[d, 0..3], RQ_dt, A'[d, 0..3], D[d], W_in_z[d, 0..63], RQ_z):
     - `b = S16; acc = sum_r mac(0, S8, DL[r]); RQ <- S; dt_pre = rq_16(acc, b); dt = softplus(dt_pre)`
     - per n (A'[d,n] = S16):
       - `bu = sh_16(B[n] * U[d], 0)` (exact)
       - `acc = mac(0, dt, A'); dA = exp2(acc)` (LUT, input raw)
       - `acc = mac(15, H_l[d,n], dA) + mac(4, dt, bu); H_l[d,n] = sh_24(acc, 0)`
     - `Dd = S8; acc = sum_n mac(11, H_l[d,n], C[n]) + mac(0, Dd, U[d]); y = sh_16(acc, 1)`
     - `acc = sum_k mac(0, S8, XN[k]); RQ <- S; z = rq_16(acc)`
     - `sig = sigmoid(z); sz = sh_16(z * sig, 15)`
     - `U[d] = sh_8(y * sz, 13)` (now holding G)
   - **out_proj**, per i (row: W_out[i, 0..95], RQ): `xr = X[i]; acc = sum_d mac(0, S8, U[d]); RQ <- S; X[i] = rq_16(acc, xr)`.
3. **Logits.** Final RMSNorm as in step 2; then per v (row: E_out[v, 0..63], RQ):
   `acc = sum_k mac(0, S8, XN[k]); RQ <- S; LOGITS[v] = rq_16(acc)`.

Accumulator bounds (all < 2^31): GEMV 96 x 127 x 127 < 2^21; mean square 64 x 2^24 = 2^30
(x = -32768 everywhere); scan 2^(23 + 15 - 15) + 2^(15 + 14 - 4) < 2^27; y 4 x 2^(23 + 7 - 11) + 2^14 < 2^21;
P 2^15 x 2^15 = 2^30; LERP 2^16 x 2^11 = 2^27; element-wise products <= 2^30.

Per token the lane executes 49,920 stream MACs plus about 9,000 other steps (norms, conv, scan,
LERP). The latency section of `arch.md` shows these hide under the stream.

## 6. On-chip memory (11 macros)

Two memories, one sequencer port, 1-clk read latency. Internal address: 12 bits.

| Memory | Macros | Organisation | Internal address |
|---|---|---|---|
| HMEM | 9 (3 triples, `GEN_H[3t + {0,1,2}]` = bytes 0, 1, 2 of entry row) | 768 x 24-bit entries; triple = entry >> 8, row = entry & 255 | 0x000-0x2FF, one entry per address |
| BMEM | 2 (`GEN_B[0]` even bytes, `GEN_B[1]` odd bytes) | 512 bytes; 16-bit access at an even address reads/writes both macros in one cycle (LE) | 0x400-0x5FF, one byte per address |

| Region | Internal | Size | Contents |
|---|---|---|---|
| H0 | 0x000 | 384 entries | state block 0, entry = 4 d + n, INT24 Q6.17 |
| H1 | 0x180 | 384 entries | state block 1 |
| XN | 0x400 | 64 B | INT8 |
| X | 0x440 | 128 B | 64 x INT16 LE |
| U | 0x4C0 | 96 B | INT8 (u, then g) |
| DBC | 0x520 | 12 B | DL, B, C |
| TMP | 0x52C | 20 B | spare |
| CONV0 | 0x540 | 96 B | xi of the previous token, INT8 |
| CONV1 | 0x5A0 | 96 B | |
| LOGITS | 0x440 (alias X + U + DBC + TMP) | 256 B | 128 x INT16 LE, written by the logits rows |

- Persistent state: H0, H1, CONV0, CONV1 = 2,304 + 192 = 2,496 B. Activations 320 B.
- The alias is legal: XN is below X, so the logits rows read XN while writing X..TMP, which are
  dead at that point.
- Host byte address (RD_MEM[_Q]): bit 12 clear -> HMEM entry `addr[11:2]`, byte `addr[1:0]`
  (byte 3 reads 0x00); bit 12 set -> BMEM byte `addr[8:0]`. So the host sees H at
  0x0000-0x0BFF (4 bytes per entry), BMEM at 0x1000-0x11FF, the logits at **0x1040**, 256 B.
- State reset (CTRL.STATE_RESET): the microcode zeroes H0, H1 (768 entry writes), CONV0 and
  CONV1 (192 byte writes); required once after power-up.

## 7. Host weight stream (per token, 54,280 bytes)

All multi-byte items little endian. `RQ` = M low byte, M high byte, s.

```
EMB     E_in[token, 0..63]                                  64 x INT16         128 B
per block:
  IN_X   for d < 96: W_in_x[d, 0..63], RQ, w0[d], w1[d], RQ_conv, cb[d]       74 B/row  7,104 B
  X_PROJ for j < 12: W_x[j, 0..95], RQ                                         99 B/row  1,188 B
  CHAN   for d < 96: b_dt[d], W_dt[d, 0..3], RQ_dt, A'[d, 0..3], D[d], W_in_z[d, 0..63], RQ_z
                                                                               85 B/row  8,160 B
  OUT    for i < 64: W_out[i, 0..95], RQ                                       99 B/row  6,336 B
LOGITS  for v < 128: E_out[v, 0..63], RQ                                      67 B/row  8,576 B
```

Total 128 + 2 x 22,788 + 8,576 = **54,280 B** (FP16: 99,840 B). The exporter writes the per-token
stream and `golden/stream.py` is its source of truth, with `unpack_stream` as the inverse.

## 8. Host protocol: what is identical and what changes

Identical to `src/docs/spec.md` section 7 and `src/rtl/io/mb_host_qspi.v`: the pad interface,
SPI mode, command set (WR_CSR 0x02, RD_CSR 0x0B, START 0x31, STREAM_Q 0x32, RD_MEM_Q 0x6B,
RD_MEM 0x03), HRDY flow control (check before every byte), the CSR map (CTRL/STATUS/byte
count/PC), STATE_RESET, the abort and reset table of section 7.1 including every "kept /
undefined" entry and the recovery rules, the host timing rules, and the sampler
(float64, greedy or softmax(logit / T), seeded, `src_int8/golden/sampler.py` semantics).

Changes forced by INT8:

| Item | FP16 | INT8 |
|---|---|---|
| Stream length | 99,840 B (FP16 words, MSB first) | 54,280 B, section 7, little endian; FIFO `TOTAL` constant and the byte-count CSR range change accordingly |
| Logits | 128 x FP16 at memory byte address 0x0800, MSB first | 128 x INT16 Q7.8 at host address **0x1040**, LE; the host divides by 256 before sampling |
| Memory read-back map | 2 x word + {0 high, 1 low} | section 6 (H entries as 4-byte slots at 0x0000, BMEM at 0x1000) |
| ID CSR | 0x4D ('M') | **0x49** ('I') |
| State-safe abort window | 262 B (first CONV0 write) | the first CONV0 write needs stream bytes up to `w1[0]`, byte index 196; the window is therefore 197 B. `ucode/tests/test_abort_rules.py` derives it from the microcode and the TB uses the derived value, exactly as in FP16 |
| Microcode PC CSR | 8 bits | 8 bits (the program has < 256 uops; the ucode test asserts it) |

The host-side changes are confined to `golden/stream.py`, `golden/memmap.py`, `golden/vectors.py`
and the demo's logit decoding.

## 9. Training (QAT) and export

- Start from the FP16 checkpoint `e96.pt` (`src/model/train.py` recipe, d_inner 96, seed 0),
  or retrain it with `src_int8/model/train.py`, which is a copy. QAT then runs 5,000 steps,
  batch 64 x 512, AdamW, peak LR 3e-4, 200 warm-up steps, cosine to 0, grad clip 1.0, seed 0.
- Fake quantisation in the forward pass (straight-through estimator for the gradient):
  - every tensor in table 3.1 is clipped and rounded to its format at the point where the chip
    stores it (XN, XI, XC, U, DL/B/C, DT_PRE, DT, DA, H, Y, Z, SZ, G, X, LOGITS). dt is
    `min(softplus(.), 8 - 2^-12)`; dA = round(exp2(dt A') * 2^15) / 2^15 with the
    `dt A' <= -16 -> 0` rule; H is clipped to +-64 after every scan step in the chunked scan
    (`src/model/scan.py` copied), without per-step rounding (the parallel scan cannot
    reproduce the recurrence rounding; the golden measures the gap);
  - weights: per-row symmetric INT8 as in 3.2, scales recomputed from the current float weights
    every step (max-abs, not learned); A' as Q8.7; cb, b_dt as Q7.8; D as INT8 s = 2^-6;
    E_in as Q7.8 and E_out as per-row INT8 (two quantisations of the one tied tensor);
  - the nonlinearities are evaluated in float, then rounded to their output formats; the LUT
    interpolation error is not modelled in training (it is <= 2 LSB and the golden has it).
- Export (`golden/weights.py`): fold the norm gains, quantise as above, compute (M, s) per row
  with 3.3, write `params/mamba_e96_int8.npz` (integer arrays plus the config), and assert
  every range in 3.2.
- Acceptance: `golden/evaluate.py` (bit-exact integer model) on the FP16 validation crops gives
  **BPB <= 1.3955** (1.3549 x 1.03). The only permitted knobs if it is missed are the QAT step
  count (up to 20k) and the peak LR (1e-4..1e-3); a format change is a revision of this document.

## 10. Golden model collateral (`src_int8/golden/`)

The modules are grouped in sub-packages (revision 1); the contents are those of the Phase 0 list.

| Module | Contents |
|---|---|
| `ops/formats.py` | table 3.1 / 3.2 as constants (name -> width, fraction bits, scale), `rsh`, `sat`, RQ bounds, row classes of 3.3 |
| `ops/lane.py` | `mac`, `dot`, `wb_sh`, `wb_rq`, `sh`, `rq` |
| `ops/nlu.py` | ROM builder (5.1), address arithmetic, `sigmoid`, `softplus`, `exp2`, `rsqrt`, `silu16` |
| `layers/{norm,conv,proj,scan,block}.py` | rmsnorm, in_x + conv, x_proj / out_proj / logits rows, channel (dt, scan step, y, gate), block: exactly the sequence of 5.2; `layers/shifts.py` derives the shifts from the formats |
| `model.py` | `HwModel` (batched, integer state, probes), `step`, `step_stream` |
| `io/weights.py` | checkpoint -> integer parameter set, (M, s) encoding, range asserts |
| `io/params.py` | parameter-set layout, range checks, `.npz` load / save |
| `io/stream.py`, `io/memmap.py` | sections 7 and 6 (`state_safe_bytes` = 197) |
| `host/{sampler,generate,evaluate}.py` | as in FP16, with INT16 logits / 256 |
| `vectors/` | chip vectors (stream, logits, H / CONV state, host image) and unit vectors (lane, wb, nlu); format in `docs/vectors.md` |
| `tests/` | lane and writeback (exhaustive rounding/saturation edges), LUT (every input of the uniform tables, all fractions of exp2 / all mantissas of rsqrt against float64), stream pack/unpack, layers vs the QAT torch ops, model determinism, accumulator bound assertions, end-to-end BPB |

The golden is pure integer arithmetic (int64 numpy with explicit width assertions); no float
enters the token step.

## Changelog

- **Revision 1 (2026-10-14).** No change to sections 2-8 (formats, arithmetic, sequence, memory,
  stream, host protocol): the golden, exporter and QAT implement them as written. Two notes:
  - Section 9: the 5,000-step / 3e-4 default missed the acceptance figure (golden 1.4092 BPB);
    the shipped model uses the two permitted knobs, 20,000 steps and peak LR 1e-3 (fake-quant
    1.3740, golden **1.3749** BPB, acceptance 1.3955). `docs/model.md` has the full table.
  - Section 10: the golden modules are grouped in sub-packages (`ops/`, `layers/`, `io/`, `host/`,
    `vectors/`); `golden/ops/formats.py` is the single copy of the format table.
