# mq_chip architecture (INT8 Mamba byte-LM)

`mq_chip` executes one token step of the model in `spec.md` per host command. It is the
`mb_chip` (FP16, `src/docs/arch.md`) microarchitecture with the arithmetic units replaced and
the memory reorganised; the sequencer, host link, CSRs and FIFO are copied and adapted.
Status: planning document (Phase 0). The figures marked "estimated" below were written before the
RTL existed; the measured values are in `rtl_units.md`, `signoff.md` and, collected, `results.md`
(53-bit uops, 221 uops, 450,412 clk/token, 323,957 um^2 placed std cells, 27.9 mW at tt).

## Block diagram

```
 pads (same as dla_fp16_chip / mb_chip)
 SCLK CS_N IO[3:0]          HRDY
   |    |    |  ^             ^
 +-v----v----v--|----+        |
 | mq_host_qspi      |  WR/RD_CSR, START, STREAM_Q, RD_MEM[_Q]      (copied: mb_host_qspi)
 |  (mq_pad_sync)    |
 +--+-------+----+---+
    |csr    |byte|start / rd_req, h_addr
 +--v---+   |    |
 |mq_csr|---+----|------ clr_state, soft reset, quad_en            (copied; ID 0x49)
 +------+   |    |
 ===========|====|=================================== mq_core =====
 |  +-------v--------+ byte/S16/S24 +------------------------------+ |
 |  | mq_stream_fifo |------------->| mq_seq                       | |
 |  | 16 B, HRDY     |<---pop(1..3)-|  mq_ucode_rom (~250 x 48 b)  | |
 |  +----------------+              |  mq_loop, mq_uop_dec, mq_agu | |
 |                                  |  mq_regfile (8 x 16 b)       | |
 |                                  |  RQ register {M, s}          | |
 |                                  +---+-----------+--------+-----+ |
 |                 a(24) b(16) ps init  |   x32, fn |        | addr, data, width
 |                     +----------------v--+  +-----v-----+  |         |
 |                     | mq_dp: mq_lane    |<-| mq_nlu    |  |         |
 |                     | 24x17 mul, rsh    |  | addr, ROM |  |         |
 |                     | INT32 acc         |->| 340x16    |  |         |
 |                     +--------+----------+  +-----------+  |         |
 |                              | acc   (shared multiplier)  |         |
 |                     +--------v----------+                 |         |
 |                     | mq_dp: mq_wb      | RQ, sh, addend, |         |
 |                     | acc*{M|1} >> s|sh |  ycnt phase     |         |
 |                     | + R, sat 8/16/24  |                 |         |
 |                     +--------+----------+                 |         |
 |                              | y                 +--------v-------+ |
 |          host bytes <--------------------------- | mq_mem_arb     | |
 |                                                  | mq_hmem 3x3    | |
 |                                                  | mq_bmem 2      | |
 |                                                  +----------------+ |
 ====================================================================
```

## Units

| Unit | Dir | Kind | Function (spec section) | Change vs FP16 |
|---|---|---|---|---|
| `mq_mul24x17` | `rtl/int/` | comb | signed 24 x 17 -> 41-bit product; the chip's only multiplier, shared by lane and writeback (`mq_dp`) | replaces `mb_fp16_mul` (11 x 11) |
| `mq_rsh` | `rtl/int/` | comb | `rsh(v, k)` as a truncating arithmetic shift plus the dropped bit (the caller's carry-in): 40 -> 32 bits (ps), 48 bits (writeback) | new |
| `mq_lane` | `rtl/lane/` | 2-stage pipe | S1 product (from `mq_dp`), S2 `acc <- base + (p >>> ps) + round bit` (4.1) | replaces the FP32 align/normalise stages; no FP32 adder |
| `mq_wb` | `rtl/lane/` | 3-stage pipe | `acc * Me` (Me = M, or 1 for `wb_sh`) in two passes of the shared multiplier, one 48-bit shift by s / sh, round bit + addend in one adder, `sat_w` (4.2) | replaces `mb_fp32_wb`; the FP16 chip had no multiplier here |
| `mq_dp` | `rtl/lane/` | wrapper | lane + writeback + the shared multiplier and its operand mux | new |
| `mq_nlu_addr` | `rtl/nonlin/` | comb | x32, fn -> i, f (11 b), sh_fn, zero flag (5.1); includes the leading-one detector and normaliser for rsqrt | integer address arithmetic; exp2 zero flag replaces the softplus bypass |
| `mq_nlu_rom` | `rtl/nonlin/` | comb | 340 x 16 b unsigned, generated from `golden/nlu.py` | integer table |
| `mq_nlu` | `rtl/nonlin/` | 1 reg stage | sequences the two LERP steps on the lane, supplies `sh_fn` to `mq_wb` | same structure as `mb_nlu` |
| `mq_seq`, `mq_loop`, `mq_uop_dec`, `mq_agu`, `mq_regfile` | `rtl/seq/` | | two-phase microcoded executor | widened fields (below); RQ register; S8/S16/S24 pops; memory width |
| `mq_ucode_rom.v`, `mq_ucode_defs.vh` | `rtl/seq/` | generated | from `ucode/program.py` | regenerated |
| `mq_hmem` | `rtl/mem/` | 9 macros | 768 x 24-bit, 3 triples (6) | new (was 5 pairs x 16 bit) |
| `mq_bmem` | `rtl/mem/` | 2 macros | 512 B, byte or aligned 16-bit access | new |
| `mq_mem_arb` | `rtl/mem/` | | sequencer / host port; host 4-byte-slot view of H (6) | adapted |
| `mq_stream_fifo` | `rtl/io/` | | 16 B; pops 1, 2 or 3 bytes; `TOTAL = 54280` | adapted |
| `mq_host_qspi`, `mq_pad_sync`, `mq_csr` | `rtl/io/` | | host link, CSRs | copied; ID 0x49 |
| `mq_core`, `mq_chip` | `rtl/top/` | | engine, pad-level top | adapted |

The nonlinear functions are the same four as in FP16 and are used in the same places, so the
microcode structure (5-uop LUT macro, loops per d / k) carries over.

## Microcode ISA (`ucode/isa.py`)

48-bit uops (FP16: 36). Fields:

| Field | Bits | Meaning |
|---|---|---|
| op | 3 | MAC, INIT, MOV, NLD, LOOP0, LOOP1, END (as FP16) |
| eol | 2 | end-of-loop bits (as FP16) |
| sa, ra / sb, rb | 3 + 3 each | sources: Z, EPS16 (the constant 16), S (stream, width from `sw`), M (memory, width from `mw`), R, Y (writeback result), N (LUT operand), A; MOV: rb = destination register, or the addend register for `Y+R` |
| wr, wm | 1 + 1 | MOV destinations (register, memory) |
| sw | 2 | stream pop width: 1, 2 or 3 bytes (3 = load RQ) |
| mw | 2 | memory access width: 8, 16 (BMEM) or 24 (HMEM) |
| ps | 4 | MAC product shift |
| wmode | 2 | writeback: SH (immediate `sh`), RQ (register), SHA (`sh` + addend R[rb]), RQA (RQ + addend) |
| sh | 5 | immediate shift, or the NLU function for NLD |
| ww | 2 | writeback width 8 / 16 / 24 / raw 32 |
| nstep | 1 | LUT operand step |
| base | 12 | address operand base (LOOP: count - 1) |
| am | 3 | +k, +d, d x 4 (as FP16) |

Rules enforced by the assembler: a 24-bit memory operand (HMEM) only on side a; at most one S
and one M per uop; `MOV M <- M` is not supported (go through a register, as FP16); the `Y`
source stalls until the lane and `mq_wb` have drained; `MOV RQ <- S` is `sw = 3`.

Execution is two-phase as in `mb_seq` (P0: stall check, SRAM read, pop, operand capture; P1:
execute). Uops issue at most every 2 clk. The lane + writeback pipeline (2 + 3 stages; the
writeback's three stages are phased by the sequencer's Y-wait counter `ycnt`, which also tells
`mq_wb` which half of acc to multiply) is one stage deeper than the FP16 one, so a `MOV dst, Y`
after the last MAC of a dot waits 4 clk instead of 3.

## Program (`ucode/program.py`), estimated

| Section | Uops (est.) | Executed per token (est.) |
|---|---|---|
| embedding | 2 | 64 |
| RMSNorm x 3 | 14 each | 3 x ~340 |
| in_x + conv + SiLU | 22 | 96 x ~84 x 2 |
| x_proj | 6 | 12 x ~100 x 2 |
| channel (dt, scan, y, z, gate) | 55 | 96 x ~145 x 2 |
| out_proj | 7 | 64 x ~100 x 2 |
| logits | 6 | 128 x ~67 |
| END / reset routine | 1 / 5 | reset: 768 + 192 writes |
| **Total** | **~250 x 48 b** | **~74k uops** |

## Memory (`mq_hmem`, `mq_bmem`, `mq_mem_arb`)

- 11 macros. HMEM = 9 (3 triples: a 24-bit entry is bytes 0/1/2 across one triple, same row).
  BMEM = 2 (even / odd bytes; an aligned 16-bit access enables both).
- One sequencer port, 1-clk read latency; the host reads while idle. Address decode is
  `addr[11]`: 0 -> HMEM (triple `addr[9:8]`, row `addr[7:0]`), 1 -> BMEM (`addr[8:0]`).
- Per access only the addressed triple (3 macros) or the addressed byte macro(s) are enabled.
- Map: `spec.md` section 6 / `golden/memmap.py`.

## Floorplan expectations

- Same die, core, pin template, PDN and clock as `mb_chip` (`src/flow/config.yaml`), so the
  flow is a copy with 11 macro instances.
- Macro grid: the FP16 columns (x = 244.90 / 601.20 / 957.50 / 1313.80) and the three FP16 rows
  (y = 157.57 / 437.50 / 717.43). Rows 0 and 1 hold 4 macros each (HMEM triples 0, 1 and two of
  triple 2), row 2 holds 3 macros (one of triple 2 and the two BMEM macros) in the three east
  columns. The NW pocket shrinks to x 40..~590 um.
- Standard-cell area (gf180mcu_as_sc_mcu7t3v3, pre-layout, `syn/synth_chip.sh` with
  `synth -booth`, 2026-10-14; the original estimate was ~220k um^2):

  | Block | um^2 | Notes |
  |---|---|---|
  | `mq_dp`: shared 24 x 17 Booth multiplier | 36.8k | one multiplier for lane and writeback |
  | `mq_dp`: lane (shift + accumulate, 79 flops) | 15.4k | |
  | `mq_dp`: writeback (48-bit shift, adder, sat, 112 flops) | 29.4k | |
  | NLU (address 8.9k, ROM 13.1k, glue) | 25.6k | |
  | sequencer + loops + AGU + decoder | ~32k | |
  | ucode ROM (221 x 53 b) | 15.2k | |
  | register file 8 x 16 | 17.1k | 128 flops + hold / read muxes |
  | stream FIFO 16 B | 25.0k | |
  | host QSPI + pad sync + CSR | 15.4k | |
  | memory wrappers and arbiter | ~4.6k | |
  | **mq_chip** | **213.9k** (8,054 cells, 819 flops) | first RTL: 307.4k, with a second (32 x 17) multiplier and two rounding adders / shifters in the writeback; FP16 `mb_chip`: 164k |

  With the FP16 repair recipe expect ~290k um^2 placed. Room: ~520k um^2 outside the macros and
  channels, so set `PL_TARGET_DENSITY_PCT` to 55-60 if 50 fails to place.
- Critical path (pre-layout OpenSTA, ss_125C_3v00, 40 ns): sequencer control flop -> multiplier
  operand mux -> Booth multiplier -> product register, 24.9 ns, slack 14.9 ns. If post-layout
  timing needs it, register the multiplier operands in `mq_dp` (the lane's S1 becomes 2 stages;
  the `Y` wait and the MAC issue rule absorb it).

## Latency estimate (25 MHz, stream SCLK = clk/4, 8 clk per byte)

| Phase | clk | ms |
|---|---|---|
| stream 54,280 B x 8 clk | 434,240 | 17.37 |
| compute not hidden by the stream (3 RMSNorms, ~340 uops each + LUT latency) | ~2,400 | 0.10 |
| START -> done | **~436,700** | **17.5** |
| STATUS + byte count + 256-B logit read-back (SCLK = clk/8) | ~4,900 | 0.20 |
| host loop per token | **~441,600** | **17.7** (57 tokens/s; FP16: 32.2 ms, 31 tokens/s) |

Stream-bound check per row (budget = bytes x 8 clk; need = uops x 2 clk + LUT latencies):
IN_X 74 B = 592 clk vs 64 MACs + ~20 uops + 1 LUT = ~190 clk; CHAN 85 B = 680 clk vs
~145 uops + 6 LUTs = ~340 clk; X_PROJ/OUT/LOGITS rows: 1 MAC per byte. Everything but the
norms hides under the stream, as in FP16. HRDY drops only during the norms and the
back-pressure of the FIFO.

## Power expectation

Half the stream time and a smaller datapath, but 3 macros enabled per state access instead of
2. Expect 15-20 mW at nom tt during a token and roughly 300-350 uJ/token (FP16: 18.2 mW,
583 uJ/token). Measured with the same SDF-GLS SAIF flow (`signoff.md`): **27.9 mW, 503 uJ/token** at
nom tt; the expectation was wrong on power (the shared array multiplier re-evaluates on every operand
change and the clock tree grew with +131 flops and the 11th SRAM, `analysis/area_power.md`), right
on the direction of the energy per token (-14 % vs FP16).

## Differences vs the FP16 chip, summary

| | mb_chip (FP16) | mq_chip (INT8), measured (`results.md`) |
|---|---|---|
| Lane | FP16 x FP16 -> FP32, RNE, 3 stages | INT24 x INT16 -> 40 b, product shift, INT32 acc, 2 stages |
| Writeback | exact 2^s scale, FTZ, RNE to FP16, saturate | acc x M >> s or >> sh, round half up, + addend, sat 8/16/24; 3 stages on the lane's multiplier |
| Registers | 8 x 16 b (FP16) | 8 x 16 b (integer) + RQ {M, s} |
| LUT inputs / outputs | FP16 | INT32 raw or Q7.8 in; Q0.15 / Q3.12 / Q6.9 out |
| Memory | 5 pairs x 256 x 16 b (10 macros) | 3 triples x 256 x 24 b + 2 x 256 x 8 b (11 macros) |
| Stream | 99,840 B | 54,280 B |
| Uop | 36 b, 201 uops | 53 b, 221 uops (estimate was 48 b, ~250) |
| Token | 801,056 clk | 450,412 clk (estimate was ~437k; the 16k difference is HRDY back-pressure, `rtl_units.md`) |
| Std cells placed / power at tt | 244,062 um^2 / 18.2 mW, 583 uJ | 323,957 um^2 / 27.9 mW, 503 uJ (estimate was ~290k um^2, 15-20 mW; see `analysis/area_power.md`) |
| Host visible | - | logits INT16 Q7.8 LE at 0x1040, ID 0x49, memory map, stream length and byte order |
