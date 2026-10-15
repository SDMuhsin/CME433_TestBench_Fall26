# mq_chip results (camera-ready summary, audited 2026-10-15)

One page of numbers for the `mq_chip` INT8 Mamba byte-LM ASIC, the twin of the FP16 `mb_chip`
(`src/docs/results.md`). Every figure cites the primary artefact it was read from; paths are relative
to `src_int8/` unless they start with `/`. Run directories under `flow/runs/` and `flow/build/` are
git-ignored but present on the signoff machine. The narrative behind each table is in `spec.md`,
`arch.md`, `rtl_units.md`, `signoff.md`, `verification.md`, `model.md`, `long_context.md`,
`../demo/README.md` and `../analysis/area_power.md`.

## 1. Architecture

| Item | Value | Artefact |
|---|---|---|
| Model | 2 x Mamba selective-SSM block, d_model 64, d_inner 96, N 4, conv 2, dt_rank 4, byte vocab 128, tied embedding; the FP16 chip's checkpoint, QAT fine-tuned (20k steps, peak LR 1e-3) | `spec.md` s.1, s.9; `model.md` s.2; `golden/params/mamba_e96_int8.npz` |
| Parameters / stream | 50,048 float parameters -> INT8 weights with per-row (M, s) requant pairs: 54,280 B streamed per token over quad SPI (FP16: 99,840 B) | `golden/io/stream.py` (`TOTAL`), `golden/tests/test_stream.py` |
| Arithmetic | INT8 x INT8 / INT24 x INT16 MACs on one shared 24 x 17 Booth multiplier, INT32 accumulator, product shift `ps`, writeback `acc * M >> s` (or `>> sh`) + addend, round half up, saturate to 8 / 16 / 24 b; INT24 Q6.17 state, Q0.15 decay; shared 340 x 16 b ROM + linear interpolation for sigmoid / softplus / exp2 / rsqrt | `spec.md` s.3-5, `golden/ops/`, `rtl/int/`, `rtl/lane/`, `rtl/nonlin/` |
| On-chip memory | 11 x `gf180mcu_ocd_ip_sram__sram256x8m8wm1`: HMEM 9 (3 triples, 768 x 24 b state), BMEM 2 (512 B activations / logits / conv state); host view 3,264 state bytes + 256 logit bytes | `golden/io/memmap.py`, `rtl/mem/`, `verification.md` |
| Control | 221 x 53-bit microcode ROM, 72,322 uops per token, two-phase sequencer, two hardware loops, RQ register; state-safe abort window 197 B | `ucode/program.py`, `ucode/isa.py`, `ucode/tests/test_abort_rules.py`, `rtl_units.md` |
| Host interface | QSPI (SCLK, CS_N, IO[3:0]) + HRDY; 11 pads, the `mb_chip` / `dla_fp16_chip` pad plan; ID CSR 0x49, logits INT16 Q7.8 LE at 0x1040 | `rtl/top/mq_chip.v`, `rtl/io/mq_csr.v`, `spec.md` s.8 |
| Process / flow | GF180MCU 5LM (gf180mcuD, open_pdks 7b70722e), `gf180mcu_as_sc_mcu7t3v3` 3.3 V cells, LibreLane 3.0.14 Classic, 40 ns clock (25 MHz), A56/ACV slot 1675 x 1110 um | `flow/config.yaml`, `flow/env.sh`, `signoff.md` |

## 2. Model quality

| Model | Validation BPB | Set | Artefact |
|---|---|---|---|
| float32 PyTorch, `mamba_e96.pt` (the FP16 chip's checkpoint) | 1.3546 | 256 crops x 1,024 B, zero state per crop | `model.md` s.1 (`model/evaluate.py`) |
| FP16 chip golden (`mb_chip`) | 1.3549 | same | `/src/docs/results.md` s.8 |
| same checkpoint through the INT8 fake quantisation, no training | 1.5412 (+13.8 %) | same | `model.md` s.1 |
| QAT checkpoint, fake-quant torch forward (`mamba_e96_qat.pt`) | 1.3740 | same | `model.md` s.2 table (`model/evaluate.py --qat`) |
| **INT8 integer golden (= the chip)** | **1.3749** (+1.5 % vs float, +1.48 % vs FP16 chip; acceptance 1.3955 = 1.3549 x 1.03) | same | `model.md` s.4, `golden/tests/test_e2e.py` (asserts <= 1.3955; 62 tests pass) |
| spec 9 default recipe (5k steps, LR 3e-4), not shipped | 1.4092 golden (misses acceptance) | same | `model.md` s.2 |
| golden vs fake-quant vs float64, state carried over 8,192 B | **1.3790** vs 1.3781 (+0.07 %) vs 1.3895 (unclipped float is the worse model) | 256 crops x 8,192 B, 2.1 M predictions | `longctx/results/lc_8k.md`, `lc_8k.log` |

Long context by position (`longctx/results/lc_8k.md`; golden / fake-quant / float64):

| positions | 0-256 | 256-512 | 512-1k | 1k-2k | 2k-4k | 4k-8k |
|---|---|---|---|---|---|---|
| golden BPB | 1.3973 | 1.3632 | 1.3702 | 1.3620 | 1.3894 | 1.3791 |
| fake-quant BPB | 1.3968 | 1.3616 | 1.3698 | 1.3617 | 1.3883 | 1.3779 |
| float64 BPB | 1.4075 | 1.3731 | 1.3800 | 1.3729 | 1.3995 | 1.3897 |
| max abs h (INT24 range +-64) | 22.9 | 22.4 | 24.8 | 23.0 | 26.6 | 26.5 |
| INT24 saturations / dA at 1 - 2^-15 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 | 0 / 0 |

The golden-to-fake-quant gap (+0.0010 +- 0.0003 BPB) does not grow with position. Decay path: dA within 2.2 LSB of
Q0.15 everywhere, 1 - dA within 1.5 % up to tau 1,000 and within 8 % up to tau 100,000; INT24 dead band only for
|h| = 0.01 at tau >= 1,000 (`longctx/results/decay.txt`, `long_context.md` s.2). Text is TinyStories-like, not
coherent, at 50k parameters (`../demo/README.md`).

## 3. Area, cells, utilisation (`flow/runs/mq_final`)

Source: `python3 flow/report/report.py mq_final` (re-run 2026-10-15; reads `*-odb-cellfrequencytables/state_out.json`
and the step states), `06-yosys-synthesis/reports/stat.rpt`, `syn/build/mq_chip.stat`.

| Metric | mq_chip (INT8) | mb_chip (FP16, `/src/flow/runs/mb_final`) |
|---|---|---|
| Die / core | 1675 x 1110 um = 1.859 mm^2 / 1.631 mm^2 (A56/ACV slot, unchanged) | same |
| SRAM macros | 11, 745,485 um^2 | 10, 677,714 um^2 |
| Std cells (excl. 32,586 fill; incl. 6,839 tap/endcap) | 20,625 | 16,967 (incl. 7,249 tap) |
| Std-cell area | 323,957 um^2 | 244,062 um^2 |
| Flops / hold buffers / repair buffers / antenna diodes | 803 / 244 / 2,231 / 2,239 | 672 / 280 / 1,656 / 1,395 |
| Clock buffers / inverters | 285 / 89 | 374 CTS cells total vs 294 (`../analysis/data/cell_growth.txt`) |
| Utilisation incl. macros (std cells only) | 65.6 % (36.6 %) | 56.5 % (25.6 %) |
| Routed wirelength | 973.5 mm | 673.6 mm |
| Flow synthesis (yosys, plain array multiplier, `SYNTH_MUL_BOOTH` false) | 8,953 cells incl. 238 tie + 11 macros, 803 flops, 229,903 um^2 (`06-yosys-synthesis/reports/stat.rpt`) | 163,057 um^2 |
| Pre-layout synthesis `syn/synth_chip.sh` (yosys `-booth` + abc, tt) | 8,054 cells, 819 flops, 213,946 um^2; ss setup slack +14.87 ns (`syn/build/mq_chip.stat`, `sta.rpt`) | 6,282 cells, 720 flops, 163,769 um^2 |
| Max-fanout items (limit 9, not a signoff criterion) | 75 per corner (675 total) | 42 |

The two synthesis figures differ because the flow does not enable yosys' Booth pass (~15k um^2, `../analysis/area_power.md`
s.1); the flop count differs (803 vs 819) because the two scripts' optimisation passes differ. 84 % of the +79.9k um^2 std-cell
gap to FP16 is made at synthesis (datapath +54k, sequencer / ROM / regfile +14k), not in PnR (`../analysis/area_power.md` s.1).

## 4. Timing

**9-corner signoff STA** (OpenSTA, SPEF, propagated clock, `flow/sdc/signoff.sdc`: 0.25 ns uncertainty, 5 % derate, 20 % IO
delays, 1.5 ns max slew, liberty max cap). Source: `flow/runs/mq_final/76-openroad-stapostpnr/state_out.json`
(`timing__{setup,hold}__ws__corner:*`), via `report.py`; the right-hand columns are the same STA with the metal fill
extracted as a grounded net (`flow/runs/mq_final_fillrc/76-openroad-stapostpnr/state_out.json`, upper bound).

| Corner | Setup slack (ns) | Hold slack (ns) | Setup with fill RC | Hold with fill RC |
|---|---|---|---|---|
| min_ff_n40C_3v60 | +25.63 | **+0.106** | +25.61 | +0.106 |
| min_tt_025C_3v30 | +21.78 | +0.203 | +21.75 | +0.203 |
| min_ss_125C_3v00 | +15.55 | +0.354 | +15.51 | +0.354 |
| nom_ff_n40C_3v60 | +25.24 | +0.107 | +25.21 | +0.107 |
| nom_tt_025C_3v30 | +21.28 | +0.204 | +21.25 | +0.204 |
| nom_ss_125C_3v00 | +14.89 | +0.355 | +14.85 | +0.355 |
| max_ff_n40C_3v60 | +24.78 | +0.108 | +24.75 | +0.108 |
| max_tt_025C_3v30 | +20.70 | +0.206 | +20.66 | +0.206 |
| max_ss_125C_3v00 | **+14.11** | +0.356 | **+14.06** | +0.357 |

- Setup / hold / max-slew / max-cap violations: 0 / 0 / 0 / 0 in every corner, with and without fill (`report.py`,
  `70..73-checker-*`). Worst setup path `u_seq.pc[2]` -> multiplier operand mux -> Booth multiplier -> `u_dp.u_wb.prod[40]`;
  worst hold `u_seq.u_rf.r[6][10]` enable loop (`signoff.md`).
- Clock skew, worst setup / hold: 0.54 / -0.57 ns (`clock__skew__worst_*` of step 76; FP16 0.45 / -0.54).
- SRAM CEN hold after the post-CTS resizer repair (244 hold buffers): +0.949 ns at max_ss, +1.089 ns at min_ff
  (`signoff.md`; pre-layout it was -1.78 ns, `syn/build/sta.rpt`).
- The STA-worst setup path is a data-dependent multiplier path that the 31-token set does not exercise (observed worst
  setup margin +19.3 ns at max_ss, below); the STA is the authority.

**SDF-annotated gate-level simulation** (Open Source CVC 7.00b + `tools/cvc_sdf.patch`, all `$setuphold/$width/$period/$recrem`
checks active, SDC pad timing, 31-token set with 2 state resets and 2 host-image read-backs, routed `final/nl`).
Source: `flow/build/sdf_gls/summary.rpt` (regenerated 2026-10-15 by `checks/summarize.py`, byte-identical),
`flow/build/sdf_gls/<run>/{gls.log,timing.rpt,coverage.rpt,margin.rpt}`.

| Run (SDF values) | Tokens bit-exact | Timing-check violations | SRAM model errors | Output-timing violations (worst settle, limit 32 ns) | SDF annotation | clk / token | Sim wall |
|---|---|---|---|---|---|---|---|
| min_ff_n40C_3v60 (min) | 31 / 31 | 0 | 0 | 0 (3.58 ns) | 61,866 / 61,866 = 100 % | 450,608 | 4.3 h |
| nom_tt_025C_3v30 (typ) | 31 / 31 | 0 | 0 | 0 (4.62 ns) | 100 % | 450,608 | 4.4 h |
| max_ss_125C_3v00 (max) | 31 / 31 | 0 | 0 | 0 (6.32 ns) | 100 % | 450,608 | 4.5 h |
| nom_tt / nom_ff / nom_ss power-activity runs (2-token story "On") | 2 / 2 each | 0 | 0 | 0 | 100 % | 450,608 | 0.5-0.7 h |
| nom_tt zero-delay reference (`NOSDF=1`) | 2 / 2 | - | 0 | - | - | 450,608 | 0.1 h |

- Checks exercised (`coverage.rpt`, identical in the three corners): 2,178 SETUP + 2,178 HOLD + 1,628 WIDTH + 11 PERIOD
  statements, 27,739 IOPATH, 28,132 INTERCONNECT; 11,320 instances with timing arcs, all in the SDF; 4,389 model timing
  checks, all with an SDF value; 388 placeholder `$recrem` (the `dfsrtp_2` RN/SN pins have no Liberty arcs); 196 (min_ff)
  / 820 (nom_tt, max_ss) negative hold limits are clamped to 0 by CVC (pessimistic).
- Negative tests fire (`*_neg_*/timing.rpt`, `summary.rpt`): SRAM `GEN_H[0]` CLK +2.0 ns at min_ff -> 628 violations,
  596 SRAM errors; flop `_16667_` (`u_host.tx_cnt[1]`) CLK +0.56 ns -> 20 hold violations; clock 16 ns at max_ss ->
  3,299,989 setup violations. Clock 22 ns at max_ss (STA WNS -3.889 ns) does **not** fire in 300k clk: the STA-worst
  path is data-dependent and carries 0.25 ns uncertainty + 5 % derate.
- Observed margins (`*_probe_*/margin.rpt`): worst hold +0.542 ns at `_16667_` (min_ff; STA +0.106 ns on a different,
  never-reported register-file path), worst setup +19.344 ns at `_15913_` (`u_dp.u_wb.y[0]`, max_ss; STA +14.11 ns).
- The 450,608 clk per token (vs 450,412 in RTL and zero-delay GLS) is a TB artefact: HRDY sampled one clock later on
  each of the 387 waits, +1 clk tail (`signoff.md`, "Gate-level simulation").

## 5. Power

Activity-based: per-pin SAIF from the SDF GLS of one full token (token 1, 'n', of the story "On") at the same corner,
window START -> end of logit readback = 455,508 clk = 18.22 ms, 39,631 of 39,776 pins annotated (the 145 others are
dangling CTS `clkload` outputs); OpenSTA `report_power` on the signoff netlist / SDC / SPEF. Energy per token = power x
18.02 ms (START -> done). Source: `flow/build/power/summary.rpt` (regenerated 2026-10-15 with `SKIP_SIM=1` from the
existing SAIFs, byte-identical), `flow/build/power/power.<corner>.<tag>.rpt`.

| Corner, SAIF activity | Sequential | Combinational | Clock | SRAM macros (11) | **Total** | **Energy / token** |
|---|---|---|---|---|---|---|
| nom tt 25C 3.30 V | 0.08 mW | 8.51 mW | 17.14 mW | 2.17 mW | **27.89 mW** | **503 uJ** |
| nom ff -40C 3.60 V | 0.09 | 10.14 | 20.24 | 2.59 | **33.06 mW** | 596 uJ |
| nom ss 125C 3.00 V | 0.06 | 7.06 | 14.34 | 1.84 | **23.29 mW** | 420 uJ |

| tt variants | Total | Energy / token | Meaning |
|---|---|---|---|
| SAIF + flop power proxy (7t5v0 `dffq`/`dffrsnq` at 3.3 V) | 31.59 mW | 569 uJ | best estimate including flop internal power (Sequential +4.74 mW, clock-net switching -1.02 mW: net +3.70 mW) |
| SAIF from zero-delay GLS | 24.50 mW | 442 uJ | glitches are 3.43 mW (40 % of combinational, 12 % of total; FP16: 3 %), mostly in the array multiplier |
| Vectorless (LibreLane default activity) | 18.89 mW | 340 uJ | under-estimates: the multiplier toggles every cycle in operation |
| Vectorless ff / ss | 22.31 / 15.79 mW | 402 / 285 uJ | `summary.rpt` vectorless rows |
| LibreLane `power__total` metric | 16.2 mW | - | this is the **max_ss** corner, vectorless (`report.py`) |

Breakdown at tt: clock 61 % (17.1 mW: 803 flop + 11 SRAM CLK pins, 285 + 89 CTS cells; no clock gating, the library has
no ICG cell), combinational 31 % (8.5 mW: the shared 24 x 17 multiplier re-evaluates on every operand change although
`issue` is high 12.3 % of cycles, 3.1 mW of it in repair buffers), SRAM 8 % (2.2 mW; TB access counts 55,938 reads +
3,736 writes x Liberty energies = 2.235 mW vs OpenSTA 2.167, 3 %). Pad power 0 (no IO cells in the block).
(`../analysis/area_power.md` s.2, `../analysis/data/pow_mq_saif.txt`.)

**Library caveats that bound the absolute numbers** (`signoff.md`, "Library caveats"):
- `gf180mcu_as_sc_mcu7t3v3` has no flop internal power and no leakage data; "Sequential internal" is 0. The proxy adds
  +3.7 mW net at tt.
- The SRAM Liberty puts the datasheet access energy on both CLK edges (677 / 750 pJ per read / write at tt): very likely a
  2x over-count, about -1.1 mW at tt. The 3.3 V table is inherited from the 5 V characterisation.
- Best estimate with both corrections: about 30.5 mW at tt (31.6 - 1.1), 550 uJ/token. IR drop is not analysed at block
  level (`RUN_IRDROP_REPORT: false`).
- Activity is one representative token; every token runs the same microcode and streams the same 54,280 bytes, so the
  token-to-token spread is small (the demo and long runs show identical cycle counts for every token).

## 6. DRC, LVS, antenna, fill

Deliverable: the filled GDS `flow/runs/mq_final/final/gds_filled/mq_chip.gds`
(sha256 `0f5ef61e1b66f3c740f09d1cefae476d7d55050477ae48a1ca6f571f200aa0fd`); the unfilled `final/gds/mq_chip.gds`
(`831c59fd9127ae7f50252106234e52d370e995c1acd25684840170ab671255fc`) is LibreLane's output. Both hashes were unchanged by
the 2026-10-15 re-checks (section 10).

| Check | Unfilled GDS | Filled GDS | Artefact |
|---|---|---|---|
| Magic DRC | 0 | 0 | `mq_final/74-misc-reportmanufacturability/state_out.json`; `mq_final_fillsignoff` (`MAGIC_DRC_USE_GDS`) |
| KLayout foundry DRC, main (variant D, deep) | 0 | 0 | `mq_final/kdrc/summary.txt` (1,087 s), `mq_final/kdrc_filled/summary.txt` (1,257 s) |
| KLayout antenna | 0 | 0 | same |
| KLayout Vn.2b via arrays | 0 | 0 | `kdrc*/via.log` |
| KLayout density, block bbox | 5 items (M1.4 29.11, M2.4 22.11, M4.4 15.59, M5.4 / MT.3 15.75 % < 30 %; M3 33.10 passes) | 2 items (M2.4 26.40 %, M4.4 21.67 %); M1 34.16, M3 39.80, M5 / MT 30.14 % pass | `kdrc*/dens/*.lyrdb`, `mq_final/fill/density.txt` |
| KLayout density, worst-case A56 die model (padring + block, rest empty) | M1.4 28.77 %, M2-M5 pass | 1 item: M1.4 29.86 % (0.14 percentage points of die area short; cleared by any Metal1 elsewhere on the die); M2-M5 31.97 / 41.93 / 38.02 / 40.50 %, COMP, Poly2 pass | `mq_final/fill/die_density.txt`, `fill/die_dens/*.lyrdb` |
| PDK dummy-metal decks DM1-DM5 | - | 0 items | `mq_final/fill/dummy/dm_counts.txt` |
| `check_fill.py` (XOR of non-dummy layers = 0, squares 2 x 2 um and floating, DM.1/2b/3/4-7/8 vs drawn metal) | - | ALL PASS | `mq_final/fill/check.txt` |
| Netgen LVS vs `final/pnl` (Magic extraction from GDS) | match, 0 errors | match, 0 errors | `mq_final/68-netgen-lvs`, `mq_final_fillsignoff/*-netgen-lvs` |
| KLayout XOR (GDS vs DEF) / illegal overlap / route DRC / OpenROAD antenna nets, pins | 0 / 0 / 0 / 0, 0 | 0 / 0 | `report.py mq_final` |

Fill: 169,738 squares (M1 23,454; M2 19,984; M3 31,158; M4 28,269; M5 66,873) in `mq_chip_*` fill cells, 2,443 s incl. all
checks (`mq_final/fill/summary.txt`). M2.4 / M4.4 cannot reach 30 % at block level under the DRM dummy rules (same two layers
as `mb_chip`, 23.80 / 23.96 % there); the DRM rule is defined over the entire die and the die model passes on M2-M5 once the
block is filled. STA with the fill as a grounded net: worst setup +14.058 ns (-53 ps), worst hold unchanged (section 4).
**Organiser confirmation that the filled GDS is the accepted deliverable (and that DM.3 is kept at the block edge) is
pending, as for `mb_chip`.**

## 7. Verification

Everything is compared bit for bit against `golden/` (the integer model of `spec.md`).

| Level | Command | Scope | Result | Artefact |
|---|---|---|---|---|
| Golden + microcode | `pytest src_int8/golden/tests src_int8/ucode` | formats, lane, writeback, LUT accuracy (all 4,097 uniform inputs, 2^19 exp2 fractions x 3 octaves, 2^17 rsqrt mantissas x 3), stream round trip, layers vs the QAT torch ops, model, end-to-end BPB; ucode encoding, generated ROM current, ISA sim 8 tokens vs `tb/ref`, abort rules (197 B) | 62 passed (55 + 7), 60 s | re-run 2026-10-15 |
| Vectors | `python3 -m src_int8.golden.vectors` | `tb/golden` regenerates byte-identical; `rtl/nonlin/mq_nlu_rom.v` == `golden/ops/nlu.py` == `tb/ref/nlu_ref.py` (340 words) | identical | `verification.md`, `tb/run_unit.sh` ROM check |
| Datapath units (iverilog) | `tb/run_unit.sh` | `rsh` 20,300, `sat` 20,024, `lane` 133,810 steps, `wb` 61,093, `nlu` 54,846 (every sigmoid / softplus input in [-2200, 2200], exp2 / rsqrt boundaries + random) | PASS, 290,073 vectors | `tb/build/*.compile.log`, re-run 2026-10-15 |
| Chip RTL | `tb/run_chip.sh` (iverilog) and `--vl` (Verilator) | 31 tokens, 2 stories, state reset between them, 128 logits per token, host image (H slots + BMEM) after each story | PASS, 450,412 clk/token | `tb/build/tb_mq_chip.log`, re-run 2026-10-15 |
| Abort / reset (spec 8 = FP16 7.1) | `tb/run_abort.sh [verilator\|iverilog]` | 129 directed + 40 random scenarios (80 for seeds 2, 3) + power-up + clean run: soft reset / STATE_RESET / START while busy, `rst_n` at every activity, CS_N mid-frame, stream errors, chain; idle-FSM, CSR, 3,264 state bytes and logit read-back after every abort; state-safe edge at 197 B from both sides | Verilator seed 1: 170 scenarios / 185 aborts / 174 tokens bit-exact / 333 state checks; seed 2: 210 / 223 / 214 / 410; seed 3: 210 / 215 / 214 / 400; iverilog 4-state seed 1: same as Verilator seed 1, 0 X on driven or control outputs | `tb/abort/results/summary.txt`, `tb/build/tb_mq_abort.*.log` |
| Closed-loop demo (Verilator) | `demo/run_demo.sh` | 4 stories (3 x 199 + 67 tokens to EOS), next byte sampled from the chip's logits, text == golden-only generation | PASS, 664 x 128 logits, 0 TB errors | `demo/build/{once_upon_a_time,lily_wanted,the_little_dog,the_quick_brown_fox}.json` |
| Long runs, one reset (Verilator) | `demo/run_long.sh val.bin --full` | forced input 2,048 and 8,192 tokens (3 and 10 EOS crossed), closed loop 1,200 tokens | all bit-exact, 0 TB errors, max abs h 17.52 / 22.94 / 12.49, 0 INT24 saturations | `demo/build/long_{forced,forced_8k,closed}/long.json` |
| Gate level, zero delay (iverilog) | `flow/gls/run_gls.sh nl / pnl` | routed netlist / powered netlist, 31 tokens, 2 state resets, 2 host-image read-backs | PASS / PASS, 450,412 clk/token, 3 h 03 min / 2 h 34 min | `flow/logs/gls_nl.log`, `flow/logs/gls_pnl.log` |
| Gate level, SDF (CVC) | `flow/sdf_gls/run_sdf_gls.sh <corner>` | min_ff / nom_tt / max_ss, 31 tokens, all timing checks | PASS x 3, 0 violations (section 4) | `flow/build/sdf_gls/summary.rpt` |

Not covered: abort behaviour at gate level (RTL only); reset recovery / removal of the 194 `dfsrtp_2` flops (no Liberty
arcs; GLS uses placeholder limits); host protocol violations that spec 8 forbids (asynchronous `rst_n` deassertion,
CS_N pulses < 2 clk, CS_N low across reset release); team A's unit-vector files (`golden/vectors/unit.py`) are not
consumed by the unit TBs, which use the independent `tb/ref` spec-formula references instead.

**RTL / netlist consistency.** Five RTL files (`rtl/top/mq_core.v`, `rtl/lane/mq_dp.v`, `rtl/lane/mq_wb.v`,
`rtl/seq/mq_loop.v`, `rtl/seq/mq_seq.v`) carry mtimes 23:21-23:22 on 2026-10-14, after the `mq_final` run started
(20:56) and after the abort runs (21:44-22:43) and the earlier chip-TB run; `rtl/top/mq_chip.v` (20:37) predates the run.
A synthesis-only LibreLane run of the current RTL (`flow/runs/audit_syn`, 2026-10-15, same config) produces a yosys
netlist **byte-identical** (modulo the header) to `flow/runs/mq_final/06-yosys-synthesis/mq_chip.nl.v`, 229,903.296 um^2
in both: the late edits are non-functional (comments / whitespace), and the hardened netlist corresponds to the current
RTL. In addition every RTL entry point of section 10 was re-run on the current RTL and passes with the signoff counts.

## 8. Throughput

| | clk / token | ms / token at 25 MHz | tokens / s |
|---|---|---|---|
| Chip, START -> done | 450,412 | 18.02 | 55.5 |
| of which the 54,280-byte stream at 8 clk/byte | 434,240 | 17.37 | |
| Host loop incl. STATUS, byte count and 256-byte logit readback (SCLK = clk/8) | 455,312 | 18.21 | 54.9 |
| State reset routine | 2,678 | 0.11 | |

Identical in RTL (iverilog and Verilator), zero-delay GLS, the demo and the long runs (`tb/build/tb_mq_chip.log`,
`flow/logs/gls_nl.log` CYCLES line, `demo/build/*.json` `avg_done_clk` / `avg_total_clk` = 450,412 / 455,312 for all 664 +
11,440 tokens). The chip is stream-bound: 72,322 uops hide under the 8-clk-per-byte stream except the three RMSNorms
(~700 clk each) and the per-channel scan loop, which together cost 387 HRDY waits = 16,172 clk above the stream floor
(`rtl_units.md`, "Cycles per token"). A 200-byte story takes 3.6 s (FP16: 6.4 s).

## 9. INT8 `mq_chip` vs FP16 `mb_chip`, side by side

Sources: this file and `/src/docs/results.md` (same flow, same die, same corners, same measurement methods).

| | mq_chip (INT8) | mb_chip (FP16) | INT8 / FP16 |
|---|---|---|---|
| Validation BPB, chip golden (float 1.3546) | 1.3749 | 1.3549 | +1.5 % |
| BPB, 8k context, state carried (golden) | 1.3790 | 1.3603 | +1.4 % |
| Stream per token | 54,280 B | 99,840 B | 0.54x |
| Microcode | 221 x 53 b, 72,322 uops/token | 201 x 36 b, 69,421 uops/token | |
| Token time, START -> done | 450,412 clk = 18.02 ms (55.5 tok/s) | 801,056 clk = 32.04 ms (31.2 tok/s) | 0.56x |
| SRAM macros | 11 (745,485 um^2) | 10 (677,714 um^2) | +1 |
| Std cells / area | 20,625 / 323,957 um^2 | 16,967 / 244,062 um^2 | 1.22x / 1.33x |
| Flops | 803 | 672 | +131 |
| Utilisation incl. macros (std cells only) | 65.6 % (36.6 %) | 56.5 % (25.6 %) | |
| Routed wirelength | 973.5 mm | 673.6 mm | 1.45x |
| Worst setup / hold slack, 9 corners | +14.11 / +0.106 ns | +18.35 / +0.104 ns | |
| Power at nom tt, SAIF (with flop proxy) | 27.9 mW (31.6) | 18.2 mW (21.3) | 1.53x |
| Energy per token at nom tt, SAIF (with proxy) | 503 uJ (569) | 583 uJ (683) | **0.86x** |
| Glitch share of total power | 12 % | 3 % | |
| DRC / LVS / antenna / fill | all clean, filled GDS 2 density items (M2.4, M4.4) | same | |
| Gate-level verification | 31-token zero-delay nl + pnl, 3-corner SDF GLS, all PASS | same | |
| Abort / reset scenarios (Verilator seed 1) | 170 scenarios / 185 aborts | 166 / 182 | |

The INT8 chip trades +1.5 % BPB and +33 % std-cell area for half the weight traffic, 1.78x the token rate and 14 % less
energy per token; it is not smaller or cooler than the FP16 chip. `../analysis/area_power.md` attributes the area gap to
synthesis (the INT8 writeback requant datapath, the wider microcode ROM, and the flow's plain array multiplier) and the
power gap to the clock tree (+131 flops, 11th SRAM, no clock gating) and to glitching in the shared array multiplier.

## 10. Remaining caveats (honest list)

1. **Power is a model, not a measurement.** No flop internal power or leakage in the AS 3V3 Liberty (+3.7 mW net by a
   5 V-library proxy), probable 2x SRAM access-energy over-count (-1.1 mW), SRAM table inherited from the 5 V
   characterisation, no IR-drop analysis. Treat 28-32 mW at tt as +-20 %.
2. **Area and power headroom is known and not taken.** `../analysis/area_power.md` identifies config-only and RTL
   changes worth ~-30k um^2 and ~-9..-11 mW (Booth multiplier in the flow, operand isolation on the shared multiplier,
   latch-based clock gating, CTS tuning), i.e. ~310-350 uJ/token. By decision none of it is applied to this tapeout:
   `mq_final` is signed off as is, and every number above is for that run.
3. **Reset recovery / removal is unchecked** for the 194 `dfsrtp_2` flops: the Liberty has no RN/SN arcs, so neither
   STA nor the SDF covers `rst_n` release. The host must deassert `rst_n` synchronously (spec 8 / FP16 7.1).
4. **Density at block level** stays below 30 % on Metal2 (26.4 %) and Metal4 (21.7 %); this is the DRM-legal fill
   ceiling and passes in the die model (M1.4 at 29.86 % there needs any Metal1 elsewhere on the die), but the organisers
   have not yet confirmed that they take the filled GDS and keep DM.3 at the block edge. `gds/` and `info.yaml` at the
   repo root still describe the unfilled `dla_engine_chip` deliverable.
5. **Abort paths are verified on RTL only**; both GLS flows run the 31-token set.
6. **One representative token per power corner**, and the STA-worst setup path (`pc` -> multiplier -> `prod[40]`) is
   not exercised by the token set (observed margin +19.3 vs STA +14.1 ns); the STA remains the authority.
7. **Timing GLS relies on a patched Open Source CVC** (two SDF-reader fixes, MIPD bypass in the generated models); the
   self-test runs before every GLS and the negative tests prove the checks fire, but no second simulator confirms the SDF
   results (Icarus ignores timing checks).
8. **75 max-fanout items** (limit 9) per corner are reported but not repaired (FP16: 42); slew and cap are clean, so this is
   a style metric only.
9. **Long-context quality** is characterised to 8 k bytes with the state carried (FP16: 32 k); the hardware-vs-fake-quant
   gap is flat at +0.07 %. The `.npz` behind `longctx/results/lc_8k.md` is not kept in the repo.
10. **Late RTL mtimes.** Five RTL files were touched after the hardening run (section 7); the synthesis-identity check and
    the full RTL re-run cover it, but there is no version-control history for `src_int8/` yet (nothing is committed).
11. **161 Verilator lint warnings** are waived by the flow (`01-verilator-lint`, `04-checker-lintwarnings`), as in FP16.
12. The model is small (50 k parameters): the generated text is TinyStories-like in rhythm and vocabulary, not coherent.

## 11. Regression re-run after the 2026-10-15 source reorganisation

The analysis scripts moved into `analysis/area/` and `analysis/power/` (runner paths and the README updated; the data
tables are unchanged). No RTL, microcode, constraints or run artefacts changed; the GDS hashes of section 6 are unchanged.
Re-run results on the current RTL:

| Entry point | Result |
|---|---|
| `pytest src_int8/golden/tests src_int8/ucode -q` | 62 passed (59.9 s) |
| `tb/run_unit.sh` | PASS, NLU ROM matches the spec tables (340 words); rsh 20,300 / sat 20,024 / lane 133,810 / wb 61,093 / nlu 54,846 vectors bit-exact |
| `tb/build_verilator.sh && tb/run_chip.sh --vl` | PASS, 31 tokens x 128 logits bit-exact, 2 state resets, 2 state read-backs, 450,412 / 455,312 clk |
| `tb/run_chip.sh` (iverilog) | PASS, 31 tokens x 128 logits bit-exact, 2 state resets, 2 state read-backs, 450,412 / 455,312 clk |
| `tb/run_abort.sh verilator` (seed 1, fresh Verilator build) | PASS: 170 scenarios, 185 aborts, 174 tokens bit-exact (logits + state), 333 state checks, state-safe edge at 197 B confirmed (same counts as the signoff run) |
| `demo/run_demo.sh --max-bytes 20 --prompt Lily` | PASS, 19 tokens x 128 logits, text == golden, 450,412 / 455,312 clk |
| `flow/report/report.py mq_final` | unchanged metrics (sections 3-4) |
| `flow/sdf_gls/checks/summarize.py flow/build/sdf_gls` | `summary.rpt` byte-identical |
| `flow/power/run_power.sh` (`SKIP_SIM=1`, existing SAIFs) | `summary.rpt` byte-identical |
| `flow/fill/checks/{check_fill,density,die_model,dummy_drc}` on the existing filled GDS (`flow/runs/mq_final/fill/audit/`) | check_fill ALL PASS; block density table identical to the signoff `fill/density.txt` (M2.4 26.40, M4.4 21.67 % LOW, rest pass); die model M1.4 29.86 % (1 item), M2-M5 pass; PDK dummy decks DM1-DM5 0 items; GDS not regenerated, sha256 unchanged |
| `flow/drc/kdrc.sh` on the filled GDS (`flow/runs/mq_final/kdrc_filled_audit/`) | main 0, antenna 0, density 2 (M2.4, M4.4), Vn.2b 0: identical to `kdrc_filled/` |
| LibreLane `--to Yosys.Synthesis` of the current RTL (`flow/runs/audit_syn`) | netlist byte-identical to `mq_final` (section 7) |
