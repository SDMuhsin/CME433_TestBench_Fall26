# mq_chip verification

Every check compares against `src_int8/golden` (the bit-exact integer model of `spec.md`) bit for
bit. Commands are in `src_int8/README.md`. Status 2026-10-15: RTL level complete; gate level
(zero-delay and SDF GLS of the hardened netlist `flow/runs/mq_final`) complete (`signoff.md`).
Every RTL entry point below was re-run on 2026-10-15 on the current RTL after the source
reorganisation (`results.md` section 10) with the same counts.

| Level | Test | Scope | Result |
|---|---|---|---|
| Golden / microcode | `pytest src_int8/golden/tests src_int8/ucode/tests` | Formats, lane, writeback, LUTs, stream round trip, layers vs the QAT ops, model, end-to-end BPB; microcode encoding, generated RTL current, ISA run vs `tb/ref`, abort rules (`test_abort_rules.py`: entries start with a LOOP uop, state-safe window = 197 B) | 55 + 7 pass |
| Vectors | `python3 -m src_int8.golden.vectors` vs `tb/golden` | The `tb/golden` chip and unit vectors (git-ignored) regenerate byte-identical from the final `params/mamba_e96_int8.npz` (31 tokens, 2 stories); `rtl/nonlin/mq_nlu_rom.v` equals `golden/ops/nlu.py`'s ROM, `params/nlu_rom.hex` and `tb/ref/nlu_ref.py` word for word (340 words) | identical |
| Datapath units | `src_int8/tb/run_unit.sh` | rsh, sat, lane, writeback, NLU (290k vectors, `rtl_units.md`) | PASS |
| Chip RTL | `src_int8/tb/run_chip.sh [--vl]` | 31 tokens, 2 stories, state reset between them, logits + H / CONV read-back | PASS, 450,412 clk/token |
| Abort / reset | `src_int8/tb/run_abort.sh [verilator\|iverilog]` | Spec 8 (= FP16 7.1): every host abort at every phase of a token step | PASS (below) |
| Long runs | `src_int8/demo/run_long.sh val.bin --full` | 2,048 + 8,192 forced and 1,200 closed-loop tokens with one reset (Verilator) | PASS (`long_context.md` 3) |
| Closed-loop demo | `src_int8/demo/run_demo.sh` | 3 stories + "The quick brown fox": 664 sampled tokens | PASS (`demo/README.md`) |
| Gate level, zero delay | `flow/gls/run_gls.sh nl / pnl` | Routed `final/nl` and powered `final/pnl`, 31 tokens, 2 state resets, 2 host-image read-backs (iverilog) | PASS / PASS, 450,412 clk/token (`flow/logs/gls_nl.log`, `gls_pnl.log`) |
| Gate level, SDF | `flow/sdf_gls/run_sdf_gls.sh <corner>` | min_ff / nom_tt / max_ss, 31 tokens, all timing checks active, 100 % annotation (CVC) | PASS x 3, 0 timing-check violations (`flow/build/sdf_gls/summary.rpt`, `signoff.md`) |

## Abort and reset paths (2026-10-14)

**Result: no RTL bug was found, and the RTL is unchanged.** The INT8 chip keeps the FP16 chip's
host link, CSRs, FIFO control and sequencer control structure (`mq_host_qspi`, `mq_csr`,
`mq_stream_fifo`, `mq_seq`), so the behaviour of `src/docs/spec.md` section 7.1 carries over
with the INT8 numbers: stream 54,280 B, logits at 0x1040, ID 0x49, state-safe window **197 B**.

### Test

- `src_int8/tb/abort/tb_mq_abort.sv` is a pad-level host, like `tb_mq_chip`, and reuses
  `tb/common/qspi_host.svh`. It is the FP16 `tb_mb_abort` ported to the byte stream, the INT16
  logits and the section-6 memory view; it is split into include files in `tb/abort/inc/`:
  - `abort_pads.svh`: pad wiring;
  - `abort_host.svh`: the abort machinery (armed frames, cut frames, the `rst_n` injector);
  - `abort_mon.svh`: monitors and coverage (X / Z, contention, drivers off in reset, landing classifier);
  - `abort_gold.svh`: golden bookkeeping and the state / logits / idle / edge checks;
  - `abort_scen.svh`: the scenarios and the run list;
  - `abort_rng.svh`: the PRNG (xorshift32, identical in both simulators).
- `src_int8/tb/abort/gen_vectors.py` writes the golden collateral for one 9-token story
  ("Once upon"): the stream and logits of every token; the golden state after every token in the
  host view (768 H entries as 4-byte slots, then CONV0 / CONV1: 3,264 bytes); a map from
  microcode pc to program section (15 sections); the stream section boundaries.
- `src_int8/tb/run_abort.sh` has two modes:
  - Verilator, 2-state. Every uninitialised flop and SRAM bit is randomised (`--x-initial unique`, seeded).
  - iverilog, 4-state, which adds the X checks.

**How aborts are injected** (as in FP16).
- *CSR aborts* (soft reset, STATE_RESET, START) are "armed": the host clocks the whole frame
  except its last SCLK rising edge, then waits for a trigger and finishes the frame. The abort
  reaches the core about 5 clk after the trigger.
- *Triggers* are a byte count plus either a delay or a sequencer activity (NLU function in
  flight, lane in flight, logit write, state write, waiting for the stream).
- *`rst_n`* is asserted asynchronously, 1-19 ns into a cycle, by a separate process while the
  host keeps streaming or reading. The host then drops its frame.
- *Pulse widths* are sub-cycle (5 ns) or 1-4 clk.
- A monitor records where every abort landed (program section x activity). The run fails if any
  required landing point is missed.

**Checks after every abort.**
- **No hang.** Every HRDY wait is bounded (2 M clk), and a per-scenario watchdog runs.
- **CSR values.** STATUS, CTRL, ID (0x49) and byte count have the spec values (the reset values after `rst_n`).
- **Idle FSMs**, hierarchically: QSPI in S_CMD, no partial byte, quad and tx_quad off, IO drivers
  off; sequencer `run`, `ph`, `tok`, `lane_issue` 0 and the lane's S1 valid bit 0; stream FIFO
  empty, `err_ovf` clear; no X in the control registers (CTRL, err_cmd, done, ycnt, FIFO
  pointers and byte count, h_addr, rd_pend, pc).
- **State.** All 3,264 host-visible state bytes (H slots 0x0000-0x0BFF, CONV 0x1140-0x11FF) are
  read back over RD_MEM_Q and must equal golden: zero after STATE_RESET; unchanged when the abort
  keeps the state; the golden state after every checked token.
- **Logits.** Logits that survive an abort are re-read and must still match golden.
- **Next tokens.** They must match golden in logits and state: after a lost state, STATE_RESET
  and the story from token 0; after a kept state, the aborted token is re-sent and the sequence continues.
- **Pad checks**, every cycle: no X/Z on any pad control output or driven IO bit after the first
  reset (iverilog); no IO contention; while `rst_n` is low all IO drivers are off and HRDY is high.

**The 197-B state-safe window** is checked from both sides. A soft reset or START after 0, 1, 2,
127, 195 or 196 accepted bytes leaves every state byte equal to golden and the re-sent token is
bit-exact. After exactly 197 bytes (`g_chk_edge`) the read-back shows CONV0[0] already changed to
the new token's xi[0] while all other 3,263 state bytes are still the old ones: the first state
write needs stream byte 196 (conv w1[0]) and nothing else, exactly as `ucode/tests/test_abort_rules.py`
derives from the microcode and `golden/io/stream.py::state_safe_bytes` states.

### Scenarios

129 directed scenarios, counting power-up. Each run adds 40 seeded random ones (80 for seeds 2
and 3) and a final clean two-token run.

| Family | Directed | Abort points |
|---|---|---|
| Soft reset in a token step | 46 | Bytes 0, 1, 2, 127, 195, 196 / 197 (the state-safe edge), 198, the start + 1 and middle of every stream section, 54,278, 54,279. Triggered: rsqrt in all three norms; exp2, softplus, sigmoid, state write and lane in flight in the scan / in_x; +300 / +500 clk inside the norms |
| Soft reset while idle | 9 | After a completed token, held while START, STREAM bytes and CTRL = 0x07 arrive (all 8 combinations); CTRL = 0x07 in one write |
| Soft reset in the state reset | 7 | 0, 1,200-1,202 (both uop phases, one of them an H entry write), 1,700 (CONV byte writes) and 2,400 clk into the ~2.6k-clk routine, and after it |
| STATE_RESET while busy | 12 | Bytes 0, 1, the rsqrt of norm0, a random point in 5 sections, exp2 in the scan, byte 54,279; twice during a state reset |
| START while busy | 10 | Bytes 0, 2, 196 (state kept: the restarted token is bit-exact), rsqrt, exp2, logits section, 54,279; three times during or after a state reset |
| `rst_n` | 34 | Every activity: wait for stream, sigmoid, softplus, exp2, rsqrt, lane in flight, logit write, state write; a random point in all 10 stream sections; logit readback (first data nibble, byte 4, byte 117, with the chip driving IO); RD_CSR; WR_CSR; twice in the state reset; idle |
| CS_N high mid-frame | 7 | Every command cut at every beat (START, STREAM_Q, a bad command, RD_MEM_Q; WR_CSR CTRL = 0x07 at beats 8-23; RD_CSR, RD_MEM and RD_MEM_Q through address, dummy and data); ~116 cut frames. A token in 12 quad pieces, and one in 6 1-bit pieces, each piece ending mid-byte and resuming from the byte count. Between pieces: memory reads while busy, a bad command, writes to RO / unmapped CSRs, quad-mode switches, a partial START, a partial CTRL = 0x07. Logit readback cut at bytes 0, 77 and 255; a state (H slot) readback cut at byte 1000 |
| Stream errors | 2 | STREAM bytes while idle; overrun with HRDY ignored (err_ovf), then soft reset and recovery |
| Chain | 1 | START, restart, STATE_RESET, soft reset in the routine, `rst_n` mid-stream, back to back |

### Results

| Run | Scenarios | Aborts | Tokens bit-exact (logits + state) | State read-back checks | Result |
|---|---|---|---|---|---|
| Verilator, seed 1 | 170 | 185 | 174 | 333 | PASS, state-safe edge confirmed (CONV0[0] 05 -> e3 after 197 bytes, all other 3,263 state bytes kept) |
| Verilator, seed 2, 80 random | 210 | 223 | 214 | 410 | PASS |
| Verilator, seed 3, 80 random | 210 | 215 | 214 | 400 | PASS |
| iverilog (4-state X checks), seed 1 | 170 | 185 | 174 | 333 | PASS. 0 X cycles on driven or control outputs (7 tolerated power-up prefetch cycles); the scenario log is identical to Verilator seed 1 |

The seed 1 run takes 67 s in Verilator after a build of about 23 min (`--x-initial unique`).

Where the aborts landed, Verilator seed 1:

| Abort | Count | Sequencer activity at landing |
|---|---|---|
| soft_reset | 78 | idle 11, wait_stream 43, wait_lane 1, nlu_rsqrt 3, lane_in_flight 3, state_write 6, uop 11 |
| STATE_RESET | 26 | idle 1, wait_stream 22, nlu_rsqrt 1, uop 2 |
| START | 24 | idle 1, wait_stream 17, nlu_exp2 1, nlu_rsqrt 1, lane_in_flight 1, state_write 2, uop 1 |
| rst_n | 57 | idle 9, wait_stream 17, wait_lane 1, nlu_sigmoid 2, nlu_softplus 1, nlu_exp2 2, nlu_rsqrt 3, lane_in_flight 9, logit_write 2, state_write 2, uop 9 |


Soft reset and `rst_n` each landed in all 15 program sections (embedding, the three norms, both
blocks' in_x / x_proj / channel / out_proj, logits, the reset routine) and in idle.

### Findings (no RTL change)

- **CSR-driven aborts land only at certain points**, as on the FP16 chip: the host must first
  close its STREAM_Q frame and a WR_CSR frame takes ~92 clk, so soft reset, STATE_RESET and START
  can land only where the sequencer waits for the stream or inside compute that needs no stream
  (the norms, the reset routine, the scan backlog after the 16-byte FIFO filled). The triggered
  "during exp2 / softplus / sigmoid" soft resets therefore landed at the next stream wait (marked
  "trigger timed out" in the scenario log); `rst_n` reaches every cycle type.
- **State-safe window = 197 B**, verified at the edge (above). The host can cancel a token early,
  re-send it, and keep its context.
- **Requests while the soft reset is held** (START, STATE_RESET, stream bytes) are not executed;
  START / STATE_RESET clear STATUS.done. The sequencer enters the run for one cycle, harmless
  because both microcode entries begin with a LOOP uop (`test_abort_rules.py` guards it).
- **Logits survive STATE_RESET** (the routine writes only H0, H1, CONV0, CONV1), but not a START.
- **X at power-up only** (iverilog): a memory read prefetches one byte past its range, so the
  power-up CONV read-back (host 0x1140-0x11FF, before any token) prefetches BMEM byte 0 (XN,
  never written yet) and drives X on IO for a few clk after the last sampled nibble, behind the
  host's last sample. The monitor tolerates only that case; after the first token no X reaches a
  driven or control output through every abort and `rst_n` that follows.

### Not covered

- Abort behaviour at gate level (the GLS flows run the 31-token set).
- Protocol violations excluded by the host timing rules: asynchronous `rst_n` deassertion, CS_N
  pulses shorter than 2 clk, and CS_N low across reset release.
