# Mamba byte-LM ASIC (`mb_chip`)

A 2-block Mamba selective-SSM text generator (d_model 64, d_inner 96, vocab 128) on the `dla_fp16_chip` silicon template (same pads and die, 10 GF180 256x8 SRAM macros, 25 MHz). Weights stream in over quad SPI on every token. The SSM and conv state stays on chip.

**Status (2026-10-14).** The RTL and the routed gate-level netlist both match `golden/` bit for bit, and physical signoff is clean (`docs/signoff.md`): 0 DRC/LVS, 9-corner STA and SDF-annotated GLS at min/nom/max with 0 violations, activity-based power 18.2 mW (583 uJ/token) at nom tt, metal fill done. In a closed-loop RTL demo, the chip generated three 200-byte stories, 597 tokens x 128 logits bit-exact, at 32.2 ms/token (31 tokens/s) at 25 MHz (`demo/README.md`). **All results on one page, with artefact paths and the remaining caveats: [`docs/results.md`](docs/results.md).**

**Flow.** The steps run in this order:
1. `model/` trains the model.
2. `golden/weights` exports the FP16 parameters, and `golden/` is the bit-exact reference.
3. `ucode/` and `rtl/` implement the chip; `tb/` verifies the units and the full chip against golden.
4. `syn/` synthesises and runs STA; `flow/` does place and route, signoff and GLS.
5. `demo/` runs closed-loop text generation on the chip.

| Path | Contents |
|---|---|
| `docs/results.md` | **Camera-ready results page**: architecture, area, timing (STA + SDF GLS), power, DRC/LVS/fill, verification, throughput, BPB, caveats; every number cites its artefact |
| `docs/spec.md` | Normative model and arithmetic contract, stream order, memory map, host protocol |
| `docs/rtl_units.md` | Datapath units (MAC lane, nonlinear unit) and their verification |
| `docs/arch.md` | Chip architecture: block diagram, microcode ISA, latency, area, timing |
| `docs/signoff.md` | Physical signoff: floorplan, 9-corner STA, GLS, SDF GLS, activity-based power, DRC/LVS, metal fill |
| `docs/verification.md` | Verification summary; abort / reset path results (spec 7.1) |
| `docs/long_context.md` | Decay accuracy near 1, BPB vs context position (8k / 32k, state carried), long RTL runs |
| `model/` | PyTorch model, data prep, training, float evaluation |
| `golden/` | Bit-exact hardware reference and its tests: `arith/` (`fp`, `nlu`), `net/` (`layers`, `model`), `data/` (`weights`, `stream`, `memmap`), `host/` (`sampler`, `generate`, `evaluate`, `vectors`), `params/` (shipped FP16 weights) |
| `ucode/` | Microcode ISA (`isa.py`), assembler (`asm.py`), token program (`program.py`), ROM generator (`gen_rom.py`), ISA simulator (`isa_sim.py`), tests |
| `scripts/` | `gen_nlu_rom.py` (NLU table RTL from golden) |
| `rtl/fpu/`, `rtl/lane/`, `rtl/nonlin/` | MAC lane and NLU (`units.f`) |
| `rtl/seq/` | Sequencer: `mb_seq` (two-phase executor), `mb_loop` (PC + hardware loops), `mb_uop_dec`, `mb_agu`, `mb_regfile`, generated `mb_ucode_rom.v` / `mb_ucode_defs.vh` |
| `rtl/mem/` | `mb_mem` (5 SRAM pairs), `mb_mem_arb` (sequencer/host port), `mb_sram_256x8` wrapper, `gf180_sram_macro.v` (black box / sim model) |
| `rtl/io/` | `mb_host_qspi` + `mb_pad_sync` (host link), `mb_csr`, `mb_stream_fifo` |
| `rtl/top/` | `mb_core` (engine), `mb_chip` (pad-level top); full source list: `rtl/chip.f` |
| `tb/unit/`, `tb/vectors/` | Unit TBs and their golden vector generators |
| `tb/chip/` | Chip TB (`tb_mb_chip.sv`) with the pad-level QSPI host model (`qspi_host.svh`) |
| `tb/abort/` | Abort / reset TB (`tb_mb_abort.sv` + `inc/*.svh`): soft reset, STATE_RESET / START while busy, `rst_n`, CS_N mid-frame, overrun; golden state + logits after each abort (`gen_vectors.py`); results in `docs/verification.md` |
| `syn/` | Yosys synthesis: `synth_units.sh` (per unit), `synth_chip.sh` (full chip + slow-corner STA) |
| `flow/` | LibreLane physical design: `config.yaml`, `build.sh`, `env.sh`, `sdc/`, `drc/` (KLayout DRC), `fill/` (metal fill), `gls/`, `sdf_gls/`, `power/`, `report/`, `common/`; see `flow/README.md`; results in `docs/signoff.md` and `docs/results.md` |
| `longctx/` | Long-context study: exhaustive decay accuracy (`decay.py`), golden vs float64 BPB by position with the state carried (`long_eval.py`, `report.py`); results in `docs/long_context.md` |
| `demo/` | Closed-loop story demo: runners `run_demo.sh`, `run_long.sh`; `host/` (golden-only `stories.py`, `chip_link.py`, `closed_loop.py`, long no-reset `long_run.py`); `tb/` (pipe-driven chip TB `tb_mb_demo.sv`, Verilator `build_verilator.sh`); results in `demo/README.md`, `docs/long_context.md` |

## Commands (from the repo root)

These need a python3 with numpy (in the nix shell, use `/usr/bin/python3` or set `PYTHON`).

```
python3 -m pytest src/golden/tests src/ucode/tests   # golden + microcode vs golden (~6 s)
src/tb/run_unit.sh                                   # datapath unit TBs (~2.5 min)
src/tb/run_chip.sh                                   # chip TB: 31 tokens, 2 stories (~8 min)
src/tb/run_chip.sh -- --story "Once upon"            # chip TB with other stories
src/tb/run_abort.sh [verilator|iverilog|all]         # abort / reset paths vs golden (Verilator ~2 min + 10 min build; iverilog X checks ~1.4 h)
src/syn/synth_chip.sh                                # synth + STA (~10 s)
python3 -m src.ucode.gen_rom                         # regenerate the microcode RTL after editing ucode/
python3 -m src.scripts.gen_nlu_rom                   # regenerate the NLU ROM RTL after editing golden/arith/nlu.py
src/flow/build.sh <TAG>                              # harden + signoff (see docs/signoff.md)
src/flow/drc/kdrc.sh <TAG> ; src/flow/fill/fill.sh <TAG>   # KLayout foundry DRC; metal fill + fill checks
python3 src/flow/report/report.py <TAG>              # signoff metrics summary
src/flow/gls/run_gls.sh [nl|pnl]                         # GLS of the routed netlist (~1.7 h)
src/flow/sdf_gls/run_sdf_gls.sh <corner>             # SDF-annotated GLS, timing checks on (~2.7 h)
src/flow/power/run_power.sh                          # activity-based power, 3 corners (~35 min)
python3 -m src.demo.host.stories                          # demo stories, golden only (~5 s)
src/demo/run_demo.sh                                 # closed-loop demo on the RTL chip, 3 x 199 tokens (~50 min)
src/demo/run_long.sh val.bin                         # Verilator RTL: 2048 forced + 1200 closed-loop tokens, no reset (~25 min)
python3 -m src.longctx.long_eval ...                 # golden vs float BPB at 8k context (docs/long_context.md)
```
