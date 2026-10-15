# mb_chip architecture

`mb_chip` runs one Mamba token step per host command. The arithmetic follows `spec.md` and matches `src/golden` bit for bit.

- **Pads.** The pad interface is the same as `dla_fp16_chip`: 11 user pins, the same pin roles, die and pad plan.
- **Weights.** They arrive on the quad-SPI weight stream in spec order. Nothing is stored on chip.
- **State.** The SSM and conv state stays in on-chip SRAM between tokens.
- **Status (2026-10-14).** RTL is complete. The chip TB passes: 31 tokens x 128 logits bit-exact, including a state reset mid-run. Synthesis is clean. The chip is placed, routed and signed off (`signoff.md`); the physical numbers below the synthesis table are pre-layout and are superseded by `signoff.md` / `results.md`.

## Block diagram

```
 pads (same as dla_fp16_chip)
 SCLK CS_N IO[3:0]          HRDY
   |    |    |  ^             ^
 +-v----v----v--|----+        |
 | mb_host_qspi      |  WR/RD_CSR, START, STREAM_Q, RD_MEM[_Q]
 |  (mb_pad_sync)    |
 +--+-------+----+---+
    |csr    |byte|start / rd_req, h_addr
 +--v---+   |    |
 |mb_csr|---+----|------ clr_state (CTRL.STATE_RESET), soft reset, quad_en
 +------+   |    |
 ===========|====|=================================== mb_core =====
 |  +-------v--------+  word  +--------------------------------+   |
 |  | mb_stream_fifo |------->| mb_seq                         |   |
 |  | 16 B, HRDY     |<-pop---|  mb_ucode_rom (201 x 36 b)     |   |
 |  +----------------+        |  mb_loop (pc, k, d loops)      |   |
 |                            |  mb_uop_dec, mb_agu, mb_regfile|   |
 |                            +---+-----------+--------+-------+   |
 |               a, b, init, scale|      ld, x|        |addr/data  |
 |                     +----------v--+  +-----v----+   |           |
 |                     | mb_lane     |<-| mb_nlu   |   |           |
 |                     | FP16xFP16   |  | ROM+addr |   |           |
 |                     | ->FP32, wb  |->| bypass   |   |           |
 |                     +-------------+ y+----------+   |           |
 |                                         +-----------v-------+   |
 |                     host bytes <--------| mb_mem_arb        |   |
 |                                         | mb_mem: 5 pairs x |   |
 |                                         | 2 x 256x8 SRAM    |   |
 |                                         +-------------------+   |
 ==================================================================
```

## Host protocol (per token)

1. `START` (0x31). The sequencer jumps to the `token` entry, and STATUS.busy rises.
2. `STREAM_Q` (0x32): 99,840 bytes, which is the `src/golden/data/stream.py` word order, MSB byte first. The host checks HRDY before each byte. Frames may be split.
3. Wait for HRDY to go high. HRDY stays low after the last byte until the step ends. Then STATUS reads `done = 1`.
4. `RD_MEM_Q` (0x6B), address 0x0800, 256 bytes: the 128 FP16 logits, MSB byte first.
   - The host's memory byte address is `2 * word + (0 = high byte, 1 = low byte)`.
   - Any memory word can be read this way while the chip is idle, which is useful for debugging state.

**New story.** Write CTRL = 0x06 (STATE_RESET plus quad_en), then wait for HRDY. This runs the microcode `reset` routine, which zeroes H0, H1, CONV0 and CONV1 in 2,772 clk, CSR write included. The host must do this once after power-up, because the SRAM contents are undefined.

**Abort and reset.** Soft reset, STATE_RESET or START while busy, `rst_n`, and CS_N deasserted mid-frame are specified in `spec.md` section 7.1, including which state and logits survive and how the host recovers. They are verified in `verification.md`.

**CSR map.** It is listed in the `mb_csr.v` header:
- ID 0x4D;
- CTRL: soft reset, STATE_RESET, quad_en;
- STATUS: busy, done, hrdy, err_cmd, err_ovf, token;
- byte count;
- microcode PC.

## Microcode ISA (`src/ucode/isa.py`)

Each uop is 36 bits:
- op;
- eol[2];
- sa / ra and sb / rb: two sources, each with a register index;
- wr, wm: MOV destinations;
- mode: writeback scale or NLU function;
- nstep;
- base[11] and am[3]: the address operand.

| Op | Effect |
|---|---|
| `MAC a, b` | One lane step `acc = RNE32(acc + a*b)`. The first MAC after an INIT starts from the init value |
| `INIT a` | Latch the accumulator init value (+0, 2^-6, bias, residual, ...) |
| `MOV dst, a` | Write R[rb] and/or MEM[addr] with a |
| `NLD fn, R` | Load the NLU (sigmoid, softplus, exp2, rsqrt) with R[ra] |
| `LOOP0 n` / `LOOP1 n` | Hardware loop. Level 0 uses counter k (innermost), level 1 uses counter d. The `eol` bit on the last body uop closes the loop, so loops cost no extra cycles |
| `END` | Stop and set STATUS.done |

**Sources.**
- `Z` gives +0 and `EPS` gives 2^-6.
- `S` is the next stream word. It stalls until a word is available.
- `M` is the SRAM word at `base + k + d` or `base + k + 4d`.
- `R0..R7` are the scalar registers.
- `Y` is the lane writeback. It stalls until the lane drains. Mode `WB0`/`WB6` uses scale 0 or -6; `WBN` uses the NLU scale and softplus bypass.
- `N` is the NLU interpolation operand: table value on side a, fraction on side b.
- `A` means "same as side a" (used for x^2).

Each uop may use at most one S and one M.

**Execution** (`mb_seq`). Each uop takes two phases:
- **P0** checks for stalls, issues the SRAM read, pops the stream word and captures operands.
- **P1** executes and writes back.

So uops run at most every 2 clk, which also satisfies `mb_lane`'s issue interval. Lane operands always come from registers.

The NLU is used through a 5-uop macro: `NLD`, `INIT Z`, `MAC N,N` (step 0), `MAC N,N` (step 1), `MOV dst, Y.WBN`.

## Program (`src/ucode/program.py` -> `src/rtl/seq/mb_ucode_rom.v`)

The program is written in Python with the builder in `src/ucode/asm.py`.
- `python3 -m src.ucode.gen_rom` regenerates the ROM, with one disassembled uop per line, and `mb_ucode_defs.vh`.
- `src/ucode/isa_sim.py` executes the encoded ROM on the golden arithmetic.
- `src/ucode/tests` checks the encoding, that the RTL is up to date, and bit-exact tokens across a state reset.

| Section | Uops | Notes |
|---|---|---|
| embedding | 2 | `MOV M[X+k] <- S` x 64 |
| RMSNorm | 13 | x^2 sum (init EPS), WB6, rsqrt, then 64 x `mul` into XN |
| in_x + conv + SiLU | 18 | per d: 64-MAC dot, conv MADD (init cb), CONV update, sigmoid, mul |
| x_proj | 5 | 12 rows x 96 |
| channel (dt, scan, D, gate) | 47 | per d: dt dot + softplus, dtu; per n: dt*A', exp2, H update; y dot; z dot; SiLU(z); gate |
| out_proj | 5 | 64 rows x 96, residual as init |
| final norm + logits | 13 + 5 | 128 rows x 64 into LOGITS (= X+U) |
| END / reset routine | 1 / 4 | reset: 240 x 4 `MOV M[4d+k] <- Z` |
| **Total** | **201 x 36 b** | 69,421 uops executed per token |

Scalars live in R0..R4. The TMP region of the memory map is spare.

## Memory (`mb_mem`, `mb_mem_arb`)

- 10 x `gf180mcu_ocd_ip_sram__sram256x8m8wm1` macros (`GEN_SRAM[2p]` = low byte, `[2p+1]` = high byte of pair p) hold 1,280 FP16 words.
- The map is `src/golden/data/memmap.py`.
- The memory has one port. Only the addressed pair is enabled, and reads have 1-clk latency.
- The sequencer owns the port while it is busy. Otherwise the host reads it.

## Latency (RTL sim, 25 MHz, stream SCLK = clk/4)

| Phase | clk | ms |
|---|---|---|
| START -> done | 801,056 | 32.04 |
| of which the stream (99,840 B x 8 clk) | 798,720 | 31.95 |
| compute not hidden by the stream (3 RMSNorms) | ~2,300 | 0.09 |
| STATUS + byte count + 256-B logit readback (SCLK = clk/8) | 4,900 | 0.20 |
| **Host loop per token** | **805,956** | **32.24** |

- The chip is stream-bound. All other compute overlaps the stream through the 16-byte FIFO. HRDY drops 195 times per token, about 12 clk each.
- After the last byte, done follows 5 clk later.

## Synthesis (`src/syn/synth_chip.sh`; yosys + abc, gf180mcu_as_sc_mcu7t3v3)

No latches, and `check -assert` is clean.

| Block | Cells | Area um^2 (tt) |
|---|---|---|
| MAC lane (mul, init, add, wb) | 2,212 | 55,630 |
| NLU (addr, ROM, frac) | 1,290 | 29,110 |
| sequencer (seq, ucode ROM 591 cells, loop, agu, regfile, dec) | 1,907 | 54,390 |
| stream FIFO | 587 | 20,100 |
| host QSPI + sync + CSR | 423 | 15,440 |
| memory glue | 146 | 3,120 |
| **mb_chip (flat)** | **6,282 (720 flops)** | **163,769** + 10 SRAM = 677,714 (LEF) |

- The base `dla_fp16_chip` has 14,221 cells and 176,720 um^2.
- **Pre-layout STA.** Measured with OpenSTA at ss_125C_3v00 with SRAM ss timing, ideal clock and no wire load.
  - Worst setup slack is **+24.27 ns** at 40 ns. The path is lane stage S3 (FP32 add normalise, `al_ms` -> `acc`), 15.5 ns.
  - SRAM Q paths have +24.3 ns of slack, and paths into the SRAM inputs have +24.6 ns.
  - The only failing check is hold into SRAM CEN, at -1.81 ns. The macro hold time is 2.96 ns and the clock is ideal. The base chip's flow repaired this same hold issue, so it is a known flow item.
