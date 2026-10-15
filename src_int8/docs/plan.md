# mq_chip plan: work split and acceptance criteria

Two teams work in parallel from `spec.md` (normative) and `arch.md`. The interface between them
is the golden model and its vectors; `golden/formats.py` is the single copy of the format table.
Nothing in `src_int8/` imports from `src/`; files are copied and adapted. Nothing is committed
until sign-off.

## Team A: QAT + golden

| Step | Deliverable | Done when |
|---|---|---|
| A1 | `golden/formats.py`, `golden/lane.py`, `golden/nlu.py` + tests | `rsh`, `sat`, `mac`, `wb_rq`, `wb_sh` tested on every edge (ties, negative ties, saturation at each width, `M` and `s` bounds); the LUT tests reproduce the accuracy figures of spec 5.1 |
| A2 | `golden/layers.py`, `golden/model.py`, `golden/stream.py`, `golden/memmap.py`, `golden/weights.py` | `step_stream` equals `step`; `unpack_stream(token_stream())` round-trips; accumulator bound assertions on; exporter asserts every range of spec 3.2 |
| A3 | `model/` (copy of `src/model/` + `qat.py`: fake-quant of spec 9) | QAT runs from `e96.pt`; `model/evaluate.py` reports the float-QAT BPB |
| A4 | `params/mamba_e96_int8.npz`, `golden/evaluate.py` result | **golden BPB <= 1.3955** on the FP16 validation crops (256 x 1024 B) |
| A5 | `golden/vectors.py`, `tb/vectors/*.py` generators, `tb/abort/gen_vectors.py`, `demo/stories.py` | the chip, unit, abort and demo vector sets exist for the shipped params |
| A6 | `longctx/` (copy, adapted) | golden vs float64 BPB by position at 8k, state carried; decay accuracy table for the Q0.15 dA |

Interim collateral for Team B before A4 is done: A2 with randomly initialised integer parameters
(any `.npz` that passes the exporter asserts) is enough for unit vectors, microcode tests and the
chip TB; the shipped weights only change the vector contents.

## Team B: RTL + flow

| Step | Deliverable | Done when |
|---|---|---|
| B1 | `ucode/` (isa, asm, program, gen_rom, isa_sim, tests) | `isa_sim` runs the ROM on the golden arithmetic and matches `HwModel` bit-exactly over a state reset; `test_abort_rules.py` derives the state-safe window |
| B2 | `rtl/alu`, `rtl/lane`, `rtl/wb`, `rtl/nonlin` + `tb/unit` | bit-exact on the golden vectors: multiplier exhaustive on INT8 x INT8 and random 24 x 16; `mq_wb` all `sh`, random `(M, s)`, saturation edges; lane dots K = 1..128 with `ps`; NLU every input of the uniform tables and random + boundary exp2/rsqrt inputs incl. the zero flag |
| B3 | `rtl/seq`, `rtl/mem`, `rtl/io`, `rtl/top`, `tb/chip` | `tb/run_chip.sh`: 31 tokens, 2 stories, state reset between them, all logits bit-exact |
| B4 | `tb/abort` | `tb/run_abort.sh` (Verilator seeds 1-3 + iverilog X checks): every spec 7.1 row, same scenario families as FP16, no RTL hang, state and next tokens bit-exact |
| B5 | `syn/` | yosys clean (`check -assert`, no latches), pre-layout OpenSTA at ss_125C_3v00 with SRAM libs: positive setup slack at 40 ns |
| B6 | `flow/` (config with 11 macros, SDCs, build, kdrc, fill, sdf_gls, power scripts copied) | signoff set below |
| B7 | `demo/` | closed-loop RTL demo, 3 x 199 tokens bit-exact; Verilator long run (2,048 forced + 1,200 closed loop, no reset) |

## Acceptance criteria (all required)

1. **Golden bit-exact with RTL.** Chip TB, abort TB, demo and long runs: every logit and every
   state read-back equals `golden/` bit for bit.
2. **QAT quality.** Golden BPB <= 1.3955 on the FP16 validation crops; the float-QAT to golden
   gap is reported.
3. **GLS bit-exact.** `flow/run_gls.sh nl` and `pnl` on the routed netlist, 31 tokens.
4. **Signoff set**, same as `src/docs/signoff.md`: 9-corner SPEF STA (0 setup / hold
   violations, 0 max-slew at 1.5 ns, max-cap within liberty limits), Magic DRC 0, KLayout
   foundry DRC main / antenna / Vn.2b 0, LVS match, XOR 0, OpenROAD antenna 0; metal fill with
   its checks (DM rules, density, filled-GDS DRC, LVS, STA with fill); SDF GLS at
   min_ff / nom_tt / max_ss with 100 % annotation, 0 timing-check violations and the negative
   tests failing as expected; activity-based power (SAIF from the SDF GLS, 3 corners, energy per
   token); abort tests (B4); long context (A6 plus the Verilator long run).
5. **Docs.** `docs/rtl_units.md`, `docs/verification.md`, `docs/signoff.md`, `docs/long_context.md`
   and `README.md` in the `src/` style, with measured numbers replacing every estimate in
   `arch.md`.

## Order of work and hand-offs

```
week 1   A1 A2 (random params)  |  B1 (isa, program on golden), B2 units
week 2   A3 A4 (QAT, export)    |  B3 chip TB on random params, B5 synth
week 3   A5 A6                  |  B3 on shipped params, B4 abort, B6 PnR
week 4   -                      |  B6 signoff + GLS + SDF GLS + power, B7 demo, docs
```

Hand-offs: A2 -> B1 (golden arithmetic for `isa_sim` and unit vectors); A4 -> B3 (shipped
params); B1 -> A5 (state-safe window value, memory map check). Any change to `spec.md`
sections 3-7 is a revision that both teams pick up through `formats.py`, `stream.py` and
`memmap.py`; the RTL takes its constants from the generated ROM and `defs.vh`, so a format
change costs a ROM regeneration, not an RTL change, unless a width changes.

## Risks and their owners

| Risk | Owner | Mitigation already in the spec |
|---|---|---|
| QAT misses 1.3955 | A | INT16 residual and LUT inputs, per-row requant, INT24 state; knobs limited to steps and LR (spec 9) |
| Scan rounding (recurrence) not modelled in training | A | measured by A4 (golden BPB) and A6 (position buckets) |
| 11-macro floorplan congestion | B | row-2 placement in the east columns, density knob (arch.md) |
| Multiplier timing | B | one multiplier per stage, split option documented |
| Byte-serial stream pops (S24) starving the FIFO | B | 16-byte FIFO holds 5 RQ loads; `room` threshold as FP16 |
