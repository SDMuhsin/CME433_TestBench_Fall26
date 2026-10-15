# Mamba byte-LM ASIC, INT8 edition (`mq_chip`)

The INT8 twin of `src/` (`mq_chip`, FP16): the same 2-block Mamba selective-SSM text generator
(d_model 64, d_inner 96, N 4, conv 2, vocab 128, ~50k parameters) on the same silicon template
(A56/ACV block, GF180MCU, 25 MHz, 256x8 SRAM macros), with INT8 weights and activations, an
INT32 accumulator, an INT24 SSM state and per-row multiplier-shift requantisation. Weights stream
in over quad SPI on every token (54,280 B, 54 % of the FP16 stream).

**Status (2026-10-14).** Team A (QAT + golden, `docs/plan.md`) is done: the QAT checkpoint and
the exported integer parameters are shipped, and the bit-exact integer golden reaches
**1.3749 BPB** on the FP16 validation crops (float 1.3546, FP16 chip 1.3549, acceptance 1.3955),
with the per-token chip vectors and unit vectors for the RTL team in place (`docs/vectors.md`).
Team B: microcode, RTL, unit / chip / abort TBs, long runs and the closed-loop demo are done and
bit-exact against the golden (`docs/verification.md`); the RTL is unchanged by verification.
The chip is hardened and signed off in `flow/runs/mq_final` (`docs/signoff.md`: 0 STA violations in
9 corners, DRC / LVS / fill clean, zero-delay GLS and 3-corner SDF GLS 31 / 31 tokens bit-exact, 27.9 mW = 503 uJ per token at tt). Nothing here imports from `src/`.
**The audited one-page summary of every number, with its artefact, is `docs/results.md`** (2026-10-15; incl. the
INT8-vs-FP16 comparison, the remaining caveats and the regression re-run after the source reorganisation).

| Path | Contents |
|---|---|
| `docs/results.md` | **Results summary (audited)**: architecture, model quality, area, 9-corner STA + SDF GLS, power, DRC / LVS / fill, verification, throughput, INT8 vs FP16, caveats, regression re-run |
| `docs/spec.md` | Normative numerics: formats, lane, writeback, LUTs, per-token sequence, memory map, stream, host protocol deltas, QAT recipe |
| `docs/arch.md` | Units, ISA, memory, floorplan, latency and area estimates, differences vs the FP16 chip |
| `docs/plan.md` | Work split (QAT + golden / RTL + flow), acceptance criteria, schedule |
| `docs/model.md` | QAT recipe, the BPB results (float / fake-quant / golden), export facts, test map |
| `docs/long_context.md` | Golden vs fake-quant vs float64 BPB by position at 8k with the state carried; dA decay accuracy; INT24 saturation check; RTL == golden over 8,192 / 2,048 / 1,200 tokens without reset |
| `docs/rtl_units.md` | RTL units, microcode, unit / chip TB coverage, synthesis area and timing, cycles per token |
| `docs/verification.md` | The verification set: golden, vectors, units, chip, abort / reset paths (coverage and findings), long runs, demo |
| `docs/signoff.md` | Physical signoff of run `flow/runs/mq_final`: metrics table, GLS, timing-annotated GLS, power, metal fill |
| `docs/vectors.md` | Format of the chip and unit vector files for the RTL team |
| `model/` | PyTorch side: `config.py`; `data/` (corpus, batches); `float/` (model, chunked scan); `qat/` (fake-quant STE, QAT forward); `train/` (float pre-training, QAT fine-tuning); `evaluate.py`; `checkpoints/` |
| `golden/ops/` | `formats.py` (the one copy of spec table 3, `rsh`, `sat`), `lane.py` (MAC, `dot`, `wb_sh`, `wb_rq`), `nlu.py` (340-word ROM, address arithmetic, LUT functions) |
| `golden/layers/` | `norm`, `conv`, `proj`, `scan`, `block`: spec 5.2 op for op; `shifts.py` derives every shift from the formats |
| `golden/io/` | `params.py` (integer parameter set, ranges, npz), `weights.py` (checkpoint -> integers, (M, s)), `stream.py` (54,280-byte stream, inverse), `memmap.py` (section 6, host view) |
| `golden/model.py`, `golden/host/` | `HwModel` (batched, integer state, `step` / `step_stream`); host sampler, generation, BPB evaluation |
| `golden/vectors/` | chip vectors (plan / stream / logits / state / host image) and unit vectors (lane, wb, nlu) |
| `golden/tests/` | 55 pytest tests: ops vs the spec formulas, layers vs the QAT torch ops, stream round trip, model, end-to-end BPB |
| `golden/params/` | `mamba_e96_int8.npz` (shipped integer parameters), `nlu_rom.hex` (the 340 x 16 ROM) |
| `scripts/gen_nlu_rom.py` | ROM RTL (`rtl/nonlin/mq_nlu_rom.v`, `mq_nlu_defs.vh`) and `nlu_rom.hex` from the golden tables |
| `longctx/` | `long_eval.py`, `report.py`, `decay.py`, `float_ref.py`; results in `longctx/results/` |
| `tb/golden/` | Generated vectors for the default stories (git-ignored; regenerate with the command below, byte-identical to the final params) |
| `ucode/` | ISA, assembler, program (221 uops), ROM generator, ISA simulator, tests (incl. the 197-B state-safe window) |
| `rtl/` | `mq_chip` RTL: `int/`, `lane/`, `nonlin/`, `seq/`, `mem/`, `io/`, `top/` (`chip.f`); generated ROMs |
| `flow/` | Physical design and signoff (LibreLane config / build, SDC, KLayout DRC, fill, GLS, SDF GLS, power, report): `flow/README.md` |
| `tb/` | `unit/` (+ `run_unit.sh`), `chip/` (+ `run_chip.sh`, `build_verilator.sh`), `abort/` (+ `run_abort.sh`), `common/` includes, `ref/` spec-formula references |
| `demo/` | Closed-loop stories and long runs on the simulated chip: `host/`, `tb/`, `run_demo.sh`, `run_long.sh`, results in `demo/README.md` |
| `syn/` | Pre-layout synthesis (`synth_chip.sh`, `synth_units.sh`: yosys `-booth` + OpenSTA, results in `docs/rtl_units.md`) |
| `analysis/` | Area / power investigation vs `mb_chip` (`area/`, `power/` scripts, `data/` tables, report `area_power.md`); analysis only, not acted on |

## Commands (from the repo root, `/usr/bin/python3`: numpy, torch, pytest)

```
python3 -m pytest src_int8/golden/tests                        # golden tests incl. end-to-end BPB (~100 s)
python3 -m pytest src_int8/golden/tests -m "not e2e"           # ~5 s
python3 -m src_int8.model.data <TinyStoriesV2-GPT4-*.txt> <out.bin>              # corpus files
python3 -m src_int8.model.train.qat --ckpt e96.pt --train-bin train.bin --val-bin val.bin \
    --out src_int8/model/checkpoints/mamba_e96_qat.pt --steps 20000 --lr 1e-3     # QAT (~17 min GPU)
python3 -m src_int8.model.evaluate <ckpt> val.bin [--qat]                         # float / fake-quant BPB
python3 -m src_int8.golden.io.weights <ckpt> src_int8/golden/params/mamba_e96_int8.npz   # export
python3 -m src_int8.golden.host.evaluate src_int8/golden/params/mamba_e96_int8.npz val.bin  # golden BPB (~1 min)
python3 -m src_int8.golden.host.generate src_int8/golden/params/mamba_e96_int8.npz --prompt "Once upon"
python3 -m src_int8.golden.vectors src_int8/tb/golden [--story "..."]            # chip + unit vectors
python3 -m src_int8.scripts.gen_nlu_rom                                          # ROM RTL + hex
python3 -m src_int8.longctx.long_eval <params.npz> <qat.pt> val.bin lc_8k.npz --fakeq-device cuda:1  # ~20 min
python3 -m src_int8.longctx.report lc_8k.npz --md ; python3 -m src_int8.longctx.decay --hist lc_8k.npz
python3 -m pytest src_int8/ucode                                                 # microcode: encoding, RTL current, ISA run, abort rules (3 s)
python3 -m src_int8.ucode.gen_rom                                                # microcode ROM RTL (rtl/seq)
src_int8/tb/run_unit.sh                                                          # datapath unit TBs, iverilog (~15 s)
src_int8/tb/build_verilator.sh && src_int8/tb/run_chip.sh --vl                   # chip TB, 31 tokens (iverilog without --vl, ~8 min)
src_int8/tb/run_abort.sh [verilator|iverilog|all] [-- +SEED=2 +NRAND=80]         # abort / reset paths (~25 min build + 1 min; iverilog ~45 min)
src_int8/demo/run_demo.sh                                                        # closed-loop stories on the RTL chip, Verilator (~1 min)
src_int8/demo/run_long.sh val.bin [--full]                                       # 2,048 forced + 1,200 closed-loop [+ 8,192 forced] tokens, no reset
```

Verification results: `docs/verification.md`; demo text and throughput: `demo/README.md`; all numbers with their
artefacts: `docs/results.md`.
