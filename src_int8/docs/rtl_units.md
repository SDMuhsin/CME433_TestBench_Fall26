# mq_chip RTL units (team B, 2026-10-14)

Bit-exact implementation of `spec.md` sections 4-8 on the `mb_chip` (FP16) microarchitecture.
Module prefix `mq_`; nothing is shared with `src/` (copied files are marked).  Status: RTL,
microcode, unit TBs, chip TB, abort TB, long runs, demo and pre-layout synthesis done
(`verification.md`, `demo/README.md`); PnR / signoff (plan B6) done in `flow/runs/mq_final`
(`signoff.md`, `results.md`).

- Sources: `rtl/chip.f` (all), `rtl/units.f` (datapath units); paths relative to `rtl/`, include
  dirs `rtl/nonlin`, `rtl/seq`.  Verilog-2001 RTL, one clock, active-low async reset on control
  state only; datapath registers have no reset.
- Generated files: `rtl/seq/mq_ucode_rom.v` + `mq_ucode_defs.vh` (`python3 -m src_int8.ucode.gen_rom`
  from `ucode/program.py`), `rtl/nonlin/mq_nlu_rom.v` + `mq_nlu_defs.vh` (team A's
  `python3 -m src_int8.scripts.gen_nlu_rom` from `golden/ops/nlu.py`).  `tb/run_unit.sh` and
  `tb/run_chip.sh` fail if they are stale (the NLU ROM is checked word for word against the spec
  5.1 tables computed independently in `tb/ref/nlu_ref.py`).
- Tool environment: `source src_int8/flow/env.sh` (copy of `src/flow/env.sh`: LibreLane 3.0.14
  nix devshell with yosys 0.62, OpenSTA, iverilog, verilator 5.044; `PDK_ROOT`).

## Units

| File | Module | Kind | Function (spec) | Origin |
|---|---|---|---|---|
| `int/mq_rsh.v` | `mq_rsh` | comb | `rsh(v, k) = (v >>> k) + v[k-1]`: truncating shift of `{v, 0}` whose LSB is the round bit, added by the caller as a carry-in (no rounding adder); parametrised widths | new |
| `int/mq_mul24x17.v` | `mq_mul24x17` | comb | signed 24 x 17 -> 41 b exact product, the chip's only multiplier (lane 24 x 16; writeback acc halves x unsigned M) | new |
| `int/mq_sat.v` | `mq_sat` | comb | `sat_w`, w by `ww` (8 / 16 / 24 / raw 32), result sign-extended to 32 b | new |
| `lane/mq_lane.v` | `mq_lane` | 2-stage pipe | `acc <- base + rsh(a * b, ps)` (4.1); S1 product (from `mq_dp`), S2 shift + add with the round bit as carry | replaces `mb_lane` |
| `lane/mq_wb.v` | `mq_wb` | 3-stage pipe | `wb_sh` / `wb_rq` as one `rsh(acc * Me, k)` (Me = M or 1) + addend + `sat_w` (4.2); acc x M in two passes of the shared multiplier, phased by the sequencer's `ycnt` | replaces `mb_fp32_wb` |
| `lane/mq_dp.v` | `mq_dp` | wrapper | lane + writeback + the shared `mq_mul24x17` and its operand mux (`issue ? a, b : wb halves`) | new |
| `nonlin/mq_nlu_addr.v` | `mq_nlu_addr` | comb | x32, fn -> ROM index, fraction f (0..2048), `sh_fn`, exp2 zero flag (5.1) | rewritten |
| `nonlin/mq_nlu_rom.v` | `mq_nlu_rom` | comb | 340 x 16 b unsigned case ROM | generated (team A) |
| `nonlin/mq_nlu.v` | `mq_nlu` | 1 reg stage | registers the address, feeds `T[i + step]` and `f` / `2^11 - f` to the lane | adapted |
| `seq/mq_seq.v` | `mq_seq` | | two-phase microcoded executor; RQ register; Y stall counter | adapted (`mb_seq`) |
| `seq/mq_uop_dec.v`, `mq_loop.v`, `mq_agu.v`, `mq_regfile.v` | | | 53-bit uop fields; PC + two hardware loops (copied); 12-bit AGU with k / 2k / d / 2d / 4d; 8 x 16 b registers (copied) | |
| `mem/mq_hmem.v` | `mq_hmem` | 9 macros | 768 x 24 b, 3 triples (6) | new |
| `mem/mq_bmem.v` | `mq_bmem` | 2 macros | 512 B, byte or aligned 16-bit LE access (6) | new |
| `mem/mq_mem.v`, `mq_mem_arb.v` | | | one port: `addr[11:10]` 0 -> HMEM, 1 -> BMEM; host 13-bit byte view (H as 4-byte slots, BMEM at 0x1000) | new / adapted |
| `mem/mq_sram_256x8.v`, `gf180_sram_macro.v` | | | macro wrapper and vendor model | copied |
| `io/mq_stream_fifo.v` | `mq_stream_fifo` | | 16 B, LE pops of 1 / 2 / 3 bytes, `TOTAL = 54280` | adapted |
| `io/mq_host_qspi.v`, `mq_pad_sync.v` | | | host link (spec 8: unchanged) | copied |
| `io/mq_csr.v` | `mq_csr` | | CSR map of the FP16 chip, **ID 0x49** | copied, ID changed |
| `top/mq_core.v`, `top/mq_chip.v` | | | engine; pad-level top with the 11 `mq_chip` pad terminals | adapted |

## mq_lane and mq_wb

```
issue c:   S1 p_r <- a * b (40 b, mq_dp multiplier)   S2 acc <- (first ? init : acc) + (p_r >>> ps) + p_r[ps-1]
           acc valid and done in cycle c + 2; issues >= 2 cycles apart (sequencer rule)
mq_wb:     Me = mode RQ ? M : 1,  k = mode RQ ? s : sh        (ph = sequencer ycnt, 0 while the lane is busy)
           ph 0  hi   <- acc[31:16] * Me                     (shared multiplier, lane idle)
           ph 1  prod <- (hi << 16) + acc[15:0] * Me          (48 b exact acc * Me)
           ph 2  y    <- sat_w((prod >>> k) + prod[k-1] + (mode A ? addend : 0))
           ph 3  y read by the sequencer
```

One multiplier (`mq_mul24x17`, Booth-encoded by yosys) serves both: it computes `a * b` in the
cycle the lane issues and belongs to the writeback otherwise.  `wb_sh` is `wb_rq` with `M = 1`,
so there is one 48-bit shifter and one adder (the addend adder takes the round bit as carry).
`mq_wb` takes `acc` and the controls of the uop that reads `Y` (`wmode`, `sh`, `ww`, `R[ra]` as
addend, the RQ register) and needs them stable from the first idle cycle; the sequencer holds a
`MOV dst, Y` / `NLD fn, Y` in P0 until the lane is idle **and** three more cycles have passed
(`ycnt`, exported as `wb_ph`), so the result of the last MAC reaches a register or memory 4 clk
after that MAC's P1 as before (lane 2 + wb 3 = the former 3 + 2; FP16: 3).  A `Y` read whose uop
arrives after the lane is already idle waits one cycle longer than before (~200 clk per token).
`init` is read in S2, i.e. one cycle after the issue; the INIT uop's P1 is >= 2 cycles after the
previous MAC's P1, and the MAC in flight does not use it.  The hardware-only detail beyond the
spec: `sat_w` works on the exact 49-bit `v`, and raw mode (`ww = 32`) passes `acc` unchanged for
the LUT inputs MS and P.

## mq_nlu

```
NLD fn, src    cycle 0: register idx = base + i, f, sh_fn, zero          (src: R sign-extended, or Y raw)
MAC N, N (0)   a = T[i],     b = 2^11 - f   first step, init 0, ps 0
MAC N, N (1)   a = T[i + 1], b = f          >= 2 cycles later
MOV dst, YN    y = zero ? 0 : sat_16(rsh(acc, sh_fn))                     (mq_wb in SH mode, shift from mq_nlu)
```

Address arithmetic exactly as spec 5.1 (`mq_nlu_addr.v` header): uniform clamp to +-2048, exp2
floor / fraction split with the `p <= -16 2^19` zero flag (the lane result is discarded; the
address fields are then don't-care), rsqrt leading-one detector + even-exponent normaliser.
Minimum `NLD -> Y` latency: 10 clk (NLD P0, two issues, lane 2, wb 3).

## Microcode (`ucode/`)

- `isa.py`: 53-bit uop (arch.md estimated 48: 4 address-mode bits for `+k / +2k / +d / +2d / +4d`
  byte addressing and separate `ps` / `sh` fields).  Fields and codes in the module docstring
  and `rtl/seq/mq_ucode_defs.vh`.  `MOV RQ <- S` is `sw = 3`; `MOV dst, YN` is a MOV with
  `nstep = 1`; `NLD` carries the function in `wmode` and may read `Y` raw.
- `program.py`: 221 uops (`token` at 0, `reset` at 215), 72,322 uops executed per token, register
  use R0..R6.  Per-scalar op order is spec 5.2; the first state write (`CONV0[0] <- xi`) is placed
  directly after the `w1` MAC so the state-safe abort window is **197 B** as spec 8 says
  (`tests/test_abort_rules.py` derives it).
- `isa_sim.py` runs the encoded ROM on the spec arithmetic (`tb/ref`); `tests/test_ucode.py`
  checks the encoding, that the generated RTL is current, the reset routine, and 8 tokens over two
  stories bit-exact against `tb/ref/model_ref.py` (logits, H, BMEM).  7 tests pass (`pytest src_int8/ucode`).

## Verification

Spec-formula references (no numpy, pure ints) live in `tb/ref/`: `intmath.py` (rsh, sat, mac,
wb), `nlu_ref.py` (ROM + 4 functions), `model_ref.py` (one token step of 5.2, random parameter
sets of 3.2, stream of section 7), `memmap.py`, `vectors.py` (unit vectors), `check_rom.py`.
Shared TB includes: `tb/common/` (`tb_report.svh`, `qspi_host.svh`).

`tb/run_unit.sh` (iverilog, ~15 s), all bit-exact:

| TB | Vectors | Coverage |
|---|---|---|
| `tb_rsh` | 20,300 | random 40-bit values, every k, ties of both signs at every k, max magnitudes (`q + rbit` vs `rsh`) |
| `tb_sat` | 20,024 | random widths 8..50 b, both saturation edges at 8 / 16 / 24, raw 32 |
| `tb_lane` | 133,810 steps | `mq_dp` with the writeback idle: GEMV K = 64 / 96 / 128 INT8 x INT8, element-wise 16 x 16, RMS mean square with init 16 and ps 6, 2-step MADD at every ps, y dot (ps 11), LERP shape, +-2^23 x +-2^15 at ps 15, ties at the product shift; issued at max rate plus random gaps, acc checked on every step |
| `tb_wb` | 61,093 | `mq_wb` + `mq_mul24x17`: random `(mode, sh, M, s, addend, ww)`, saturation edges at every width, `(M, s)` bounds, ties of `wb_sh` and `wb_rq`, raw mode; one vector per 4 cycles through the ph 0..3 protocol |
| `tb_nlu` | 54,846 | `mq_nlu` + `mq_dp`; sigmoid / softplus: every x in [-2200, 2200] + random INT32 + extremes; exp2: 20k random over the live range + random INT32 + all boundaries (0, -2^19 +- 1, -16 2^19 +- 1, -2^31); rsqrt: 20k random over every octave 16 .. 2^32 - 1 + boundaries; checks idx, f, sh_fn, zero and the 16-bit result |

Team A's unit vectors (`docs/vectors.md`, different record layout) are not consumed yet.

`tb/run_chip.sh` (`--vl` for the Verilator image from `tb/build_verilator.sh`, ~1 s/token;
iverilog ~15 s/token): pad-level host BFM, CSR reset values and err_cmd, per token STATE_RESET
(first token of a story) / START / STREAM_Q with HRDY checks / STATUS / byte count / RD_MEM_Q of
the logits at 0x1040, and at the end of each story the host image (H slots 0x0000..0x0BFF,
BMEM 0x1040..0x11FF).  Result on team A's default vectors (shipped params, 2 stories, 31 tokens):
**PASS, 31 x 128 logits and both state read-backs bit-exact**.  Team A's golden, `tb/ref`
and `isa_sim` also agree with each other on all 31 tokens (checked offline).

## Synthesis (`syn/synth_units.sh`, `syn/synth_chip.sh`; yosys 0.62 `synth -booth` + abc, gf180mcu_as_sc_mcu7t3v3 tt)

No latches, `check -assert` clean.  Cell costs in this library: flop 59 um^2, mux2 26, xor 31,
full adder (maj3 + 2 xnor) 88, so multipliers and wide adders dominate.

| Unit | Cells | Flops | Area um^2 | Before (2026-10-14 a.m.) |
|---|---|---|---|---|
| mq_rsh (40 -> 32) | 162 | 0 | 4,120 | 8,008 (41-bit rounding adder) |
| mq_mul24x17 (Booth) | 1,445 | 0 | 36,803 | mq_mul24x16 51,311 (plain array) |
| mq_sat | 130 | 0 | 2,654 | 2,654 |
| mq_lane (without the multiplier) | 519 | 79 | 15,371 | 75,985 incl. multiplier, 3 stages, 177 flops |
| mq_wb (without the multiplier) | 1,079 | 112 | 29,359 | 101,392 incl. its own 32 x 17 multiplier, 49-bit rounding adder, two shifters |
| **mq_dp** (multiplier + lane + wb) | **3,067** | 191 | **82,401** | 177,377 (lane + wb) |
| mq_nlu_addr | 428 | 0 | 8,932 | 8,932 |
| mq_nlu_rom | 631 | 0 | 13,094 | 12,930 |
| mq_nlu | 1,197 | 27 | 25,633 | 25,633 |
| **mq_chip** (SRAMs black-boxed) | **8,054** | 819 | **213,946** (+ 11 macros, 745,485 um^2 LEF) | 307,368 (11,929 cells, 950 flops) |

Root causes of the 307k: two full multipliers (the writeback had its own 32 x 17 array,
operating on the whole INT32 acc; 65k of the 101k), two 49 / 33-bit rounding adders and two
barrel shifters where one of each suffices (`wb_sh` is `wb_rq` with `M = 1`; round half up is a
truncating shift plus its dropped bit), and yosys' default array multiplier (Booth saves 30 %).
The rest of the chip (sequencer 21k, ucode ROM 15k, regfile 17k, FIFO 25k, host 13k, NLU 26k,
glue) is unchanged.  Pre-layout OpenSTA at ss_125C_3v00, 40 ns, no wire load: **worst setup
slack 14.87 ns** (path 24.9 ns: sequencer control flop -> multiplier operand mux -> Booth
multiplier -> `p_r` / `hi`); SRAM setup paths clean (`syn/build/sta.rpt`).  The min-delay report
shows the SRAM `CEN` pins' 2.94 ns library hold time against a 1.2 ns ideal-clock path from the
memory-enable flop (`mq_mem_arb` / `mq_mem`, RTL untouched); PnR hold repair buffers it as on
the FP16 chip.

## Cycles per token

| | clk | ms @ 25 MHz |
|---|---|---|
| issue estimate from the ucode (72,322 uops x 2 + Y waits, `isa_sim.cycles`) | 153,874 | 6.2 |
| stream floor 54,280 B x 8 clk | 434,240 | 17.37 |
| arch.md estimate START -> done | ~436,700 | 17.5 |
| **measured START -> done** (chip TB, 31 tokens) | **450,412** (450,217 before the shared-multiplier writeback) | **18.02** |
| measured incl. STATUS + byte count + 256 B logit read-back | 455,312 | 18.2 (55 tokens/s; FP16: 31) |
| state reset | 2,678 | 0.11 |

The token is stream-bound; the 16k clk above the floor are HRDY back-pressure (387 host waits
per token): the three RMSNorms (~700 clk each without stream consumption) and the per-channel
scan loop, which consumes only the 8 A' bytes in ~190 clk so the 16-byte FIFO fills.  A 32-byte
FIFO or loading the A' words before the loop would recover most of it (tuning, not required).

## Open items

- `host.memh` from team A zeroes the XN region (0x1000..0x103F); the chip holds XN there.  The TB
  checks only the bytes `docs/vectors.md` defines.
- Consume team A's unit vectors (`golden/vectors/unit.py`) in addition to `tb/ref`.
