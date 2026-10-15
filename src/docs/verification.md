# mb_chip verification

Every check compares against `src/golden` bit for bit. Commands are in `src/README.md`.

| Level | Test | Scope | Result |
|---|---|---|---|
| Golden / microcode | `pytest src/golden/tests src/ucode/tests` | Arithmetic, NLU, stream, model, microcode encoding, ISA run vs golden, abort rules (`test_abort_rules.py`) | 22 pass |
| Datapath units | `src/tb/run_unit.sh` | FP16 mul, FP32 add, writeback, lane, NLU (2.0 M vectors) | PASS (`rtl_units.md`) |
| Chip RTL | `src/tb/run_chip.sh` | 31 tokens, 2 stories, state reset between them | PASS |
| Abort / reset | `src/tb/run_abort.sh` | Spec 7.1: every host abort at every phase of a token step | PASS (see below) |
| Long runs | `src/demo/run_long.sh` | 8,192 + 2,048 forced and 1,200 closed-loop tokens with no reset (Verilator) | PASS (`long_context.md`) |
| Closed-loop demo | `src/demo/run_demo.sh` | 3 x 199 sampled tokens | PASS (`demo/README.md`) |
| Gate level | `src/flow/gls/run_gls.sh nl / pnl` | Routed netlist, 31 tokens, zero delay | PASS (`signoff.md`) |
| Gate level, timing | `src/flow/sdf_gls/run_sdf_gls.sh <corner>` | Routed netlist + SDF (min_ff / nom_tt / max_ss), active setup/hold/width/period checks, SDC pad timing, 31 tokens; negative tests and margin probes | see `signoff.md` "Timing-annotated GLS" |

## Abort and reset paths (2026-10-14)

**Result: no RTL bug was found, and the RTL is unchanged.** This closes the open risk "the soft-reset / abort path is untested". The behaviour is now normative in `spec.md` section 7.1.

### Test

- `src/tb/abort/tb_mb_abort.sv` is a pad-level host, like `tb_mb_chip`, and reuses `qspi_host.svh`. It is split into include files in `tb/abort/inc/`:
  - `abort_pads.svh`: pad wiring;
  - `abort_host.svh`: the abort machinery;
  - `abort_mon.svh`: monitors and coverage;
  - `abort_gold.svh`: golden bookkeeping;
  - `abort_scen.svh`: the scenarios;
  - `abort_rng.svh`: the PRNG.
- `src/tb/abort/gen_vectors.py` writes the golden collateral for one 9-token story:
  - the stream and logits of every token;
  - the golden state after every token (H0, H1, CONV0, CONV1);
  - a map from microcode pc to program section.
- `src/tb/run_abort.sh` has two modes:
  - Verilator, 2-state. Every uninitialised flop and SRAM bit is randomised (`--x-initial unique`, seeded).
  - iverilog, 4-state, which adds the X checks.

**How aborts are injected.**
- *CSR aborts* (soft reset, STATE_RESET, START) are "armed": the host clocks the whole frame except its last SCLK rising edge, then waits for a trigger and finishes the frame. The abort reaches the core about 5 clk after the trigger.
- *Triggers* are a byte count plus either a delay or a sequencer activity (NLU function in flight, lane in flight, logit write, state write, waiting for the stream).
- *`rst_n`* is asserted asynchronously, 1-19 ns into a cycle, by a separate process while the host keeps streaming or reading. The host then drops its frame.
- *Pulse widths* are sub-cycle (5 ns) or 1-4 clk.
- A monitor records where every abort landed (program section x activity). The run fails if any required landing point is missed.

**Checks after every abort.**
- **No hang.** Every HRDY wait is bounded, and a per-scenario watchdog runs.
- **CSR values.** STATUS, CTRL, ID and byte count have the spec 7.1 values (the reset values after `rst_n`).
- **Idle FSMs.** These are checked hierarchically:
  - QSPI: S_CMD, no partial byte, quad and tx_quad off, IO drivers off;
  - sequencer: run, ph and tok are 0, no lane issue;
  - lane pipeline empty;
  - stream FIFO empty and err_ovf clear;
  - no X in the control registers.
- **State.** All 960 state words are read back over RD_MEM_Q and must equal golden:
  - zero after STATE_RESET;
  - unchanged when spec 7.1 says "kept";
  - after every checked token, the golden state.
- **Logits.** Logits that spec 7.1 keeps are re-read and must still match golden.
- **Next tokens.** They must match golden in logits and state. The expectation depends on the case:
  - after a lost state: STATE_RESET, then the story from token 0;
  - after a kept state: the aborted token is re-sent, continuing the sequence.
- **Pad checks**, every cycle:
  - no X/Z on any pad control output (OE, IE, pulls, HRDY) or driven IO bit, after the first reset (iverilog);
  - no IO contention;
  - while `rst_n` is low, all IO drivers are off and HRDY is high.

### Scenarios

There are 125 directed scenarios, counting power-up. Each run adds 40 seeded random ones (80 for seeds 2 and 3) and a final clean two-token run.

| Family | Directed | Abort points |
|---|---|---|
| Soft reset in a token step | 44 | Bytes 0, 1, 2, 127, 261 / 262 (the state-safe edge), the start + 1 and middle of every stream section, 99,838, 99,839. Triggered: rsqrt in all three norms; exp2, softplus, sigmoid, state write and lane in flight in the scan / in_x; +300 / +500 clk inside the norms |
| Soft reset while idle | 9 | After a completed token, held while START, STREAM bytes and CTRL = 0x07 arrive (all 8 combinations); CTRL = 0x07 in one write |
| Soft reset in the state reset | 6 | 0, 1,200-1,202 (both uop phases, one of them a state write) and 2,600 clk into the 2,772-clk routine, and after it |
| STATE_RESET while busy | 12 | Bytes 0, 1, the rsqrt of norm0, a random point in 5 sections, exp2 in the scan, byte 99,839; twice during a state reset |
| START while busy | 10 | Bytes 0, 2, 261 (state kept: the restarted token is bit-exact), rsqrt, exp2, logits section, 99,839; three times during or after a state reset |
| `rst_n` | 34 | Every activity: wait for stream, sigmoid, softplus, exp2, rsqrt, lane in flight, logit write, state write; a random point in all 10 stream sections; logit readback (first data nibble, byte 4, byte 117, with the chip driving IO); RD_CSR; WR_CSR; twice in the state reset; idle |
| CS_N high mid-frame | 6 | Every command cut at every beat (START, STREAM_Q, a bad command, RD_MEM_Q; WR_CSR CTRL = 0x07 at beats 8-23; RD_CSR, RD_MEM and RD_MEM_Q through address, dummy and data); ~116 cut frames. A token in 12 quad pieces, and one in 6 1-bit pieces, each piece ending mid-byte and resuming from the byte count. Between pieces: memory reads while busy, a bad command, writes to RO / unmapped CSRs, quad-mode switches, a partial START, a partial CTRL = 0x07. Logit readback cut at bytes 0, 77 and 255 |
| Stream errors | 2 | STREAM bytes while idle; overrun with HRDY ignored (err_ovf), then soft reset and recovery |
| Chain | 1 | START, restart, STATE_RESET, soft reset in the routine, `rst_n` mid-stream, back to back |

### Results

| Run | Scenarios | Aborts | Tokens bit-exact (logits + state) | State read-back checks | Result |
|---|---|---|---|---|---|
| Verilator, seed 1 | 166 | 182 | 169 | 325 | PASS |
| Verilator, seed 2, 80 random | 206 | 220 | 209 | 402 | PASS |
| Verilator, seed 3, 80 random | 206 | 212 | 209 | 392 | PASS |
| iverilog (4-state X checks), seed 1 | 166 | 182 | 169 | 325 | PASS. 0 X cycles on driven or control outputs; the scenario log is identical to Verilator seed 1 |

The seed 1 run takes 96 s in Verilator, after a build of about 10 min, and 81 min in iverilog.

Where the aborts landed, Verilator seed 1:

| Abort | Count | Sequencer activity at landing |
|---|---|---|
| soft reset | 75 | idle 11, wait for stream 38, rsqrt 3, lane in flight 7, state write 5, other uop 11 |
| STATE_RESET | 26 | idle 1, wait for stream 21, rsqrt 1, lane in flight 1, other uop 2 |
| START | 24 | idle 1, wait for stream 16, exp2 2, rsqrt 2, state write 2, other uop 1 |
| `rst_n` | 57 | idle 9, wait for stream 21, sigmoid 2, softplus 1, exp2 2, rsqrt 3, lane in flight 6, logit write 2, state write 4, other uop 7 |

Soft reset and `rst_n` each landed in all 15 program sections: embedding, the three norms, both blocks' in_x / x_proj / channel / out_proj, logits, the reset routine and idle.

### Findings (behaviour now specified; no RTL change)

- **CSR-driven aborts land only at certain points.** Soft reset, STATE_RESET and START can land only where the sequencer waits for the stream, or inside compute that needs no stream (norms, the reset routine, a scan backlog). The host must first close its STREAM_Q frame, and a WR_CSR frame takes about 92 clk to clock in. A soft reset "during a logit write" or "during exp2" is therefore physically unreachable; the triggered attempts landed at the next stream wait. `rst_n` reaches every cycle type.
- **State-safe window.** An abort before stream byte 262 leaves the state intact. The host can cancel a token early, re-send it, and keep its context (tested; derived in `test_abort_rules.py`).
- **Requests while the soft reset is held.** A START or STATE_RESET that arrives while the soft reset is held is not executed, but it clears STATUS.done. The sequencer still enters the run for one cycle, and this is harmless only because both microcode entries begin with a LOOP uop. `test_abort_rules.py` now guards that property. Making the abort dominant in `mb_seq` would remove the dependency, but it is not needed and would mean re-hardening.
- **X at power-up only.** The one X the iverilog run sees is a simulation artifact of SRAM that has never been written:
  - Every memory read prefetches one byte past its range.
  - The power-up state read-back (bytes 0-1919, done before any token) therefore prefetches XN, which no run has written yet.
  - The prefetched byte reaches IO for a few clk after the last sampled nibble. On silicon it would be random bits that the host does not sample.
  - The X then stays on MISO_OUT behind OE = 0 until the next read.

  The monitor tolerates only that case. After the first token, and through every abort and `rst_n` that follows, no X reaches a driven or control output.
- **Logits survive STATE_RESET.** The reset routine zeroes only words 0x000-0x3BF, so the logits stay valid after it, but not after a START.

### Not covered

- Abort behaviour at gate level. The abort TB was run on RTL only; both GLS flows (zero-delay and SDF-annotated) run the 31-token set.
- Protocol violations excluded by spec 7.1 host timing: asynchronous `rst_n` deassertion, CS_N pulses shorter than 2 clk, and CS_N low across reset release.
