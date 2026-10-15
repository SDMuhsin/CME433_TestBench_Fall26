# mb_chip results (camera-ready summary, audited 2026-10-14)

One page of numbers for the `mb_chip` Mamba byte-LM ASIC. Every figure cites the primary artefact it
was read from; paths are relative to `src/` unless they start with `/`. Run directories under
`flow/runs/` and `flow/build/` are git-ignored but present on the signoff machine. The narrative
behind each table is in `spec.md`, `arch.md`, `signoff.md`, `verification.md`, `long_context.md`
and `../demo/README.md`.

## 1. Architecture

| Item | Value | Artefact |
|---|---|---|
| Model | 2 x Mamba selective-SSM block, d_model 64, d_inner 96, N 4, conv 2, dt_rank 4, byte vocab 128, tied embedding | `spec.md` s.1, `golden/params/mamba_e96_fp16.npz` |
| Parameters | 50,048 float; 49,920 FP16 words (99,840 B) streamed per token over quad SPI | `golden/data/stream.py` (`stream_words(cfg)` = 49,920) |
| Arithmetic | FP16 storage, FP16 x FP16 -> exact FP32 product, one RNE32 add per MAC, RNE/FTZ/saturating FP16 writeback; shared 340-word ROM + linear interpolation for sigmoid / softplus / exp2 / rsqrt | `spec.md` s.3-4, `golden/arith/` |
| On-chip memory | 10 x `gf180mcu_ocd_ip_sram__sram256x8m8wm1` (5 hi/lo pairs, 1,280 words); 1,204 words used: 1,920 B persistent SSM + conv state, 488 B activations | `golden/data/memmap.py` (`memory_map`, `sram_summary`) |
| Control | 201 x 36-bit microcode ROM, 69,421 uops per token, 1,201 per state reset; two-phase sequencer, hardware loops | `ucode/program.py`, `ucode/isa_sim.py` (`UcodeMachine.run`) |
| Host interface | QSPI (SCLK, CS_N, IO[3:0]) + HRDY; 11 pads, the `dla_fp16_chip` pad plan | `rtl/top/mb_chip.v`, `spec.md` s.7 |
| Process / flow | GF180MCU 5LM (gf180mcuD, open_pdks 7b70722e), `gf180mcu_as_sc_mcu7t3v3` 3.3 V cells, LibreLane 3.0.14, 40 ns clock (25 MHz) | `flow/config.yaml`, `flow/env.sh` |

## 2. Area, cells, utilisation (`flow/runs/mb_final`)

Source: `python3 flow/report/report.py mb_final` (reads `*-odb-cellfrequencytables/state_out.json`).

| Metric | mb_chip | dla_fp16_chip (`/librelane/runs/fp16_final`) |
|---|---|---|
| Die / core | 1675 x 1110 um = 1.859 mm^2 / 1.631 mm^2 (A56/ACV slot, unchanged) | same |
| SRAM macros | 10, 677,714 um^2 | 8, 542,171 um^2 |
| Std cells (excl. 33,127 fill; incl. 7,249 tap/endcap) | 16,967 | 14,221 (incl. 7,984 tap) |
| Std-cell area | 244,062 um^2 | 176,720 um^2 |
| Flops / hold buffers / repair buffers / antenna diodes | 672 / 280 / 1,656 / 1,395 | 485 / 213 / 995 / 826 |
| Utilisation incl. macros (std cells only) | 56.5 % (25.6 %) | 44.1 % (16.2 %) |
| Routed wirelength | 673.6 mm | 408.2 mm |
| Pre-layout synthesis (yosys/abc, tt) | 6,282 cells, 720 flops, 163,769 um^2 | `syn/build/mb_chip.stat` |

## 3. Timing

**9-corner signoff STA** (OpenSTA, SPEF, propagated clock, `flow/sdc/signoff.sdc`: 0.25 ns uncertainty, 5 % derate, 20 % IO delays).
Source: `flow/runs/mb_final/76-openroad-stapostpnr/state_out.json` (`timing__{setup,hold}__ws__corner:*`), via `report.py`.

| Corner | Setup slack (ns) | Hold slack (ns) |
|---|---|---|
| min_ff_n40C_3v60 | +28.19 | **+0.104** |
| min_tt_025C_3v30 | +25.13 | +0.200 |
| min_ss_125C_3v00 | +19.11 | +0.350 |
| nom_ff_n40C_3v60 | +27.84 | +0.105 |
| nom_tt_025C_3v30 | +24.69 | +0.201 |
| nom_ss_125C_3v00 | +18.75 | +0.351 |
| max_ff_n40C_3v60 | +27.41 | +0.105 |
| max_tt_025C_3v30 | +24.16 | +0.202 |
| max_ss_125C_3v00 | **+18.35** | +0.352 |

- Setup / hold / max-slew (1.5 ns) / max-cap (liberty) violations: 0 / 0 / 0 / 0 in every corner. Max-fanout (limit 9): 42 per corner, not a signoff criterion (`design__*_violation__count`).
- Clock skew, worst setup / hold: 0.45 / -0.54 ns (`clock__skew__worst_*`). Against the PDK default 0.2 pF the design would show 18 cap violators at max_ss, led by the two SRAM clock buffers at 1.80 / 1.75 pF (re-checked 2026-10-14 with `report_check_types -max_cap` on the signoff corner; policy as `/docs/dla_fp16_chip.md`).
- SRAM CEN hold after the post-CTS repair: +0.82 ns at max_ss, +1.01 ns at min_ff (`report_checks -path_delay min -to */CEN`, same STA setup, `flow/common/sta_corner.tcl`).
- With the metal fill extracted as a grounded net (`flow/runs/mb_final_fillrc`): worst setup +18.340 ns, worst hold +0.1043 ns, 0 violations; total net C +0.54 % nom / +0.60 % max (`flow/fill/rc/spef_delta.py mb_final mb_final_fillrc`).

**SDF-annotated gate-level simulation** (Open Source CVC, all `$setuphold/$width/$period/$recrem` checks active, SDC pad timing, 31-token set with 2 state resets).
Source: `flow/build/sdf_gls/summary.rpt`, `flow/build/sdf_gls/<run>/{gls.log,timing.rpt,coverage.rpt,margin.rpt}`.

| Run (SDF values) | Tokens bit-exact | Timing-check violations | SRAM model errors | Output-timing violations (worst settle) | SDF annotation | clk / token | Sim wall |
|---|---|---|---|---|---|---|---|
| min_ff_n40C_3v60 (min) | 31 / 31 | 0 | 0 | 0 (2.50 ns) | 44,231 / 44,231 = 100 % | 801,252 | 2.6 h |
| nom_tt_025C_3v30 (typ) | 31 / 31 | 0 | 0 | 0 (3.23 ns) | 100 % | 801,252 | 2.7 h |
| max_ss_125C_3v00 (max) | 31 / 31 | 0 | 0 | 0 (4.42 ns) | 100 % | 801,252 | 2.8 h |
| nom_tt, powered netlist `final/pnl` | 2 / 2 | 0 | 0 | 0 (3.23 ns) | 100 % | 801,252 | 0.2 h |
| nom_tt / nom_ff / nom_ss power-activity runs | 2 / 2 each | 0 | 0 | 0 | 100 % | 801,252 | 0.3 h each |

- Checks exercised: 1,344 flop `$setuphold` pairs, 1,344 `$width`, 382 placeholder `$recrem`, 1,070 SRAM checks (`coverage.rpt`). 691 negative hold limits are clamped to 0 (pessimistic).
- Negative tests fire (`*_neg_*/timing.rpt`): SRAM CLK +2.0 ns -> 637 violations; flop `_11466_` CLK +0.60 ns -> 115; SCLK synchroniser CLK +0.55 ns -> 149,630; clock 18 ns at max_ss -> 687 setup violations and wrong logits.
- Observed margins (`*_probe_*/margin.rpt`): worst hold +0.447 ns at `_11664_` (min_ff; STA slack +0.17 + 0.25 uncertainty + derate), SRAM pins >= +1.071 ns; worst setup +20.85 ns (max_ss), SRAM pins >= +24.96 ns.
- The 801,252 clk per token (vs 801,056 in RTL and zero-delay GLS) is a TB artefact: HRDY sampled one clock later, 195 waits per token.

## 4. Power

Activity-based: per-pin SAIF from the SDF GLS of one full token at the same corner (window START -> end of logit readback, 806,152 clk = 32.246 ms, 28,353 of 28,464 pins annotated; the 111 others are dangling `clkload*` outputs). Energy per token = power x 32.04 ms (START -> done).
Source: `flow/build/power/summary.rpt`, `flow/build/power/power.<corner>.<tag>.rpt`.

| Corner, SAIF activity | Sequential | Combinational | Clock | SRAM macros | **Total** | **Energy / token** |
|---|---|---|---|---|---|---|
| nom tt 25C 3.30 V | 0.05 mW | 1.99 mW | 13.89 mW | 2.27 mW | **18.20 mW** | **583 uJ** |
| nom ff -40C 3.60 V | 0.06 | 2.38 | 16.43 | 2.70 | **21.58 mW** | 691 uJ |
| nom ss 125C 3.00 V | 0.04 | 1.65 | 11.60 | 1.93 | **15.21 mW** | 487 uJ |

| tt variants | Total | Energy / token | Meaning |
|---|---|---|---|
| SAIF + flop power proxy (7t5v0 `dffq`/`dffrsnq` at 3.3 V) | 21.33 mW | 683 uJ | best estimate including flop internal power (Sequential +3.98 mW, clock-net switching -0.45 mW) |
| SAIF from zero-delay GLS | 17.70 mW | 567 uJ | glitches are 0.52 mW (26 % of combinational, 3 % of total) |
| Vectorless (LibreLane default activity) | 22.53 mW | 722 uJ | combinational 4x too high, SRAM 17x too low |
| Vectorless ff / ss | 26.72 / 18.77 mW | 856 / 601 uJ | `76-openroad-stapostpnr/<corner>/power.rpt` |
| LibreLane `power__total` metric | 19.41 mW | - | this is the **max_ss** corner, vectorless (`max_ss_125C_3v00/power.rpt`) |

Breakdown at tt: clock network 76 % (13.9 mW: 9.2 mW CTS buffer internal + 4.7 mW net switching, 10 SRAM CLK pins at 0.29 pF and 672 flop CLK pins every cycle), SRAMs 12 %, datapath 11 %. Data activity is low: 577 net transitions per clk on 8,345 nets (`flow/build/power/vcd2saif.nom_tt_025C_3v30.power.log`). Pad power is 0 (no IO cells in the block).

**Library caveats that bound the absolute numbers** (`signoff.md`, "Liberty limitations"):
- `gf180mcu_as_sc_mcu7t3v3` has no flop internal power and no leakage data; "Sequential internal" is 0 and std-cell leakage is 0. The proxy adds about +3.1 mW at tt.
- The SRAM Liberty puts the datasheet access energy (read 338.7 / write 375.0 pJ) on both CLK edges, so OpenSTA charges 677 / 750 pJ per access: very likely a 2x over-count, about -1.1 mW at tt. The TB access counts (105,092 reads, 3,760 writes in the window) x Liberty energies agree with OpenSTA's macro power within 1.5 % (2.296 vs 2.266 mW), so the state-probability model is not the issue.
- Best estimate with both corrections: about 20.2 mW at tt (proxy 21.3 - 1.1). The SRAM 3.3 V power table is inherited from the 5 V characterisation.
- IR drop is not measured at block level (`RUN_IRDROP_REPORT: false`).

## 5. DRC, LVS, antenna, fill

Deliverable: the filled GDS `flow/runs/mb_final/final/gds_filled/mb_chip.gds` (sha256 `7961ea1b...39d18d`); the unfilled `final/gds/mb_chip.gds` (`8393a3dc...b8e59b`) is LibreLane's output.

| Check | Unfilled GDS | Filled GDS | Artefact |
|---|---|---|---|
| Magic DRC | 0 | 0 | `mb_final/*-misc-reportmanufacturability/state_out.json`; `mb_final_fillsignoff` (`MAGIC_DRC_USE_GDS`) |
| KLayout foundry DRC, main (variant D, deep, 660 rule categories) | 0 | 0 | `mb_final/kdrc/summary.txt` (476 s), `mb_final/kdrc_filled/summary.txt` (531 s all four checks) |
| KLayout antenna (11 rules) | 0 | 0 | same (314 s) |
| KLayout Vn.2b via arrays (Via1-4; no Via5) | 0 | 0 | `kdrc*/via.log` |
| KLayout density, block bbox | 6 items (M1-M5, MT < 30 %) | 2 items (M2.4 23.80 %, M4.4 23.96 %) | `kdrc*/dens/*.lyrdb`, `mb_final/fill/density.txt` |
| KLayout density, worst-case A56 die model (padring + block, rest empty) | M1 28.42 % | 1 item: M1.4 29.51 % (cleared by >= 1.35 % Metal1 anywhere else on the die); M2-M5, COMP, Poly2 pass | `mb_final/fill/die_density.txt`, `fill/die_dens/*.lyrdb` |
| PDK dummy-metal decks DM1-DM5 | - | 0 | `mb_final/fill/dummy/dm_counts.txt` |
| `check_fill.py` (XOR of 24 non-dummy layers = 0, all squares 2 x 2 um and floating, DM.2b/3/4-7/8 vs drawn metal) | - | ALL PASS | `mb_final/fill/check.txt` |
| Netgen LVS vs `final/pnl` (Magic extraction from GDS) | match, 0 errors | match, 0 errors | `mb_final/*-misc-reportmanufacturability`, `mb_final_fillsignoff/*-netgen-lvs` |
| KLayout XOR (GDS vs DEF) / illegal overlap / route DRC / OpenROAD antenna nets, pins | 0 / 0 / 0 / 0, 0 | 0 / 0 | `report.py mb_final` |

Fill: 218,123 squares (M1 23,525; M2 21,061; M3 49,335; M4 42,094; M5 82,108) in 10 new `mb_chip_*FILL*` cells, 1,222 s (`mb_final/fill/fill.log`). Block coverage M1 27.49 -> 32.55 %, M2 19.27 -> 23.80, M3 28.60 -> 39.21, M4 14.90 -> 23.96, M5 14.57 -> 32.23 (`fill/density.txt`). M2.4 / M4.4 cannot reach 30 % at block level under the DRM dummy rules (DM.3/DM.4-7 leave 16.1 % / 26.5 % of the block fillable, at <= 40 % pattern coverage), and the DRM rule is defined over the entire die; the die model passes on M2-M5 once the block is filled (`signoff.md`, "Metal fill and density").

## 6. Verification

Everything is compared bit for bit against `golden/`.

| Level | Command | Scope | Result | Artefact |
|---|---|---|---|---|
| Golden + microcode | `pytest src/golden/tests src/ucode/tests` | arithmetic, exhaustive NLU error bounds, stream, model, ucode encoding, ISA sim vs golden, abort rules | 22 passed | re-run 2026-10-14 |
| Datapath units (iverilog) | `tb/run_unit.sh` | `fp16_to_fp32` 65,536 (exhaustive), `fpu_mac` 300,064, `fp32_wb` 547,566, `lane` 914,400 steps, `nlu` 215,043 (exhaustive, 4 functions) | PASS, 2.04 M vectors | `tb/build/`, re-run 2026-10-14 |
| Chip RTL (iverilog) | `tb/run_chip.sh` | 31 tokens, 2 stories, state reset between them, 128 logits each | PASS, 801,056 clk/token | `tb/build/tb_mb_chip.log` |
| Abort / reset (spec 7.1) | `tb/run_abort.sh` | 125 directed + 40 random scenarios (80 for seeds 2, 3): soft reset, STATE_RESET / START while busy, `rst_n`, CS_N mid-frame, overrun; idle-FSM, CSR, 960-word state and logit read-back after every abort | Verilator seed 1: 166 scenarios / 182 aborts / 169 tokens bit-exact / 325 state checks; seed 2: 206 / 220 / 209 / 402; seed 3: 206 / 212 / 209 / 392; iverilog 4-state seed 1: same as Verilator seed 1, 0 X on driven or control outputs | `tb/build/tb_mb_abort.*.log`, `tb/build/abort_s3/`, `tb/build/abort_iv2/` |
| Closed-loop demo (iverilog) | `demo/run_demo.sh` | 3 stories x 199 sampled tokens, next byte sampled from the chip's logits, text == golden-only generation | PASS, 597 x 128 logits, 0 TB errors | `demo/build/{once_upon_a_time,lily_wanted,the_little_dog}.json` |
| Long runs, no reset (Verilator) | `demo/run_long.sh`, `demo/host/long_run.py` | forced input 2,048 and 8,192 tokens (3 and 10 EOS crossed), closed loop 1,200 tokens | all bit-exact, 0 TB errors, max abs h 11.9 / 16.5 / 7.4 | `demo/build/long_{forced,forced_8k,closed}/long.json` |
| Gate level, zero delay (iverilog) | `flow/gls/run_gls.sh nl / pnl` | routed netlist, 31 tokens | PASS / PASS, 801,056 clk/token, 1 h 47 min / 1 h 39 min | `flow/logs/gls_nl.log`, `flow/logs/gls_pnl.log` |
| Gate level, SDF (CVC) | `flow/sdf_gls/run_sdf_gls.sh` | min_ff / nom_tt / max_ss, 31 tokens, all timing checks | PASS x 3, 0 violations (table in s.3) | `flow/build/sdf_gls/summary.rpt` |

Not covered: abort behaviour at gate level (RTL only); reset recovery/removal of the 191 `dfsrtp_2` flops (no Liberty arcs; GLS uses placeholder limits); host protocol violations that spec 7.1 forbids.

## 7. Throughput

| | clk / token | ms / token at 25 MHz | tokens / s |
|---|---|---|---|
| Chip, START -> done | 801,056 | 32.04 | 31.2 |
| of which the 99,840-byte stream at 8 clk/byte | 798,720 | 31.95 | |
| Host loop incl. STATUS, byte count and 256-byte logit readback (SCLK = clk/8) | 805,956 | 32.24 | 31.0 |

Identical in RTL, zero-delay GLS and the Verilator long runs (`flow/logs/gls_nl.log` CYCLES line, `demo/build/*.json` `avg_done_clk` / `avg_total_clk`). The chip is stream-bound: 69,421 uops of compute hide under the 16-clk-per-word stream except the three RMSNorms (about 2,300 clk). Energy per token at nom tt: 583 uJ (SAIF), about 680 uJ with the flop proxy.

## 8. Model quality

| Model | Validation BPB | Set | Artefact |
|---|---|---|---|
| float32 PyTorch, d_inner 96 | 1.3546 | 256 crops x 1,024 B, zero state per crop | `model/evaluate.py` output (scratch `eval_e96.txt`) |
| golden hardware arithmetic, d_inner 96 (= the chip) | **1.3549** (+0.02 %) | same | `golden/host/evaluate.py` output (scratch `eval_e96.txt`) |
| float32 / golden, d_inner 64 (fallback, not built) | 1.4604 / 1.4604 | same | scratch `eval_e64.txt` |
| golden vs float64, state carried over 8,192 B | 1.3603 vs 1.3596 (+0.051 %), worst bucket +0.062 % | 256 crops | `longctx/results/lc_8k.md` |
| golden vs float64, state carried over 32,768 B | 1.3550 vs 1.3542 (+0.059 %), worst bucket +0.064 % | 64 crops | `longctx/results/lc_32k.md` |
| ablation: exact 2^p decay instead of the FP16 LUT | +0.052 % overall, same shape | 128 crops x 8 k | `longctx/results/lc_8k_floatdecay.md` |

The FP16 decay dA is ideal-rounding accurate near 1 (max rel. error 2.5e-4), but 1 - dA is quantised to 2^-11, so time constants above about 4,110 tokens freeze (0.34 % of decay evaluations, `longctx/results/decay.txt`, `dA==1 frac` column of `lc_*.md`). RMSNorm's sum x^2 never saturates on 64 x 1k validation crops: largest pre-rounding value 663.6 against the 65,504 limit (re-run 2026-10-14 with the `satcheck` probe, 0 saturations). Text is locally fluent but semantically loose at 50 k parameters (`../demo/README.md`).

## 9. Remaining caveats (honest list)

1. **Power is a model, not a measurement.** No flop internal power or leakage in the AS 3V3 Liberty (+3.1 mW by a 5 V-library proxy), probable 2x SRAM access-energy over-count (-1.1 mW), SRAM table inherited from the 5 V characterisation, no IR-drop analysis. Treat 18-21 mW at tt as +-20 %.
2. **Reset recovery / removal is unchecked** for the 191 `dfsrtp_2` flops: the Liberty has no RN/SN arcs, so neither STA nor the SDF covers `rst_n` release. The host must deassert `rst_n` synchronously (spec 7.1).
3. **Density at block level** stays below 30 % on Metal2 (23.8 %) and Metal4 (24.0 %); this is the DRM-legal fill ceiling and passes in the die model, but the organisers have not yet confirmed that they take the filled GDS and keep DM.3 at the block edge. `gds/` and `info.yaml` at the repo root still describe the unfilled `dla_engine_chip` deliverable.
4. **Abort paths are verified on RTL only**; both GLS flows run the 31-token set.
5. **Vectors exercise one representative token per power corner** and the STA-worst setup path (SRAM 1 -> SRAM 7) is not exercised by the token set; the STA remains the authority for those paths.
6. **Timing GLS relies on a patched Open Source CVC** (two SDF-reader fixes, MIPD bypass in the generated models); the self-test in `flow/sdf_gls/checks/model_selftest` runs before every GLS and the negative tests prove the checks fire, but no second simulator confirms the SDF results (Icarus ignores timing checks).
7. **42 max-fanout violations** (limit 9) per corner are reported but not repaired; slew and cap are clean, so this is a style metric only.
8. **Long-context quality** is characterised to 32 k bytes with the state carried; the hardware/float gap plateaus at +0.06 % BPB. The paired hardware-vs-exact-decay table in `long_context.md` comes from `.npz` outputs that are not kept in the repo.
9. The model is small (50 k parameters): generated text is TinyStories-like in rhythm and vocabulary, not coherent.

## 10. Regression re-run after the 2026-10-14 source restructure

The source tree was reorganised (golden/ subpackages, flow/{sdc,drc,gls,report}, fill/{gen,checks,rc}, demo/{host,tb}, tb/abort/inc). No RTL, microcode, constraints or run artefacts changed; the GDS hashes above are unchanged. Re-run results:

| Entry point | Result |
|---|---|
| `pytest src/golden/tests src/ucode/tests` | 22 passed (6.2 s) |
| `tb/run_unit.sh` | PASS, all 5 units + NLU ROM up to date |
| `tb/run_chip.sh` | PASS, 31 tokens x 128 logits bit-exact, 2 state resets, 801,056 / 805,956 clk |
| `tb/run_abort.sh verilator` (seed 1, fresh Verilator build) | PASS: 166 scenarios, 182 aborts, 169 tokens bit-exact, 325 state checks (same counts as the signoff run) |
| `demo/run_demo.sh --max-bytes 20 --prompt Lily` | PASS, 19 tokens x 128 logits, text == golden, 801,056 / 805,956 clk |
| `flow/drc/kdrc.sh` on the filled GDS (`flow/runs/mb_final/kdrc_filled_audit/`) | main 0, antenna 0, density 2 (M2.4, M4.4), Vn.2b 0: identical to `kdrc_filled/` |
| `flow/fill/checks/{density,die-model density,check_fill,dummy_drc}` on the existing filled GDS (`flow/runs/mb_final/fill/audit/`) | outputs identical to the signoff `fill/*.txt` (coverage to all digits, check_fill ALL PASS, DM decks 0); GDS not regenerated, sha256 unchanged |
| `flow/report/report.py mb_final` | unchanged metrics (s.2-3) |
| `flow/sdf_gls/run_sdf_gls.sh nom_tt_025C_3v30`, 3 tokens (`flow/build/sdf_gls/nom_tt_025C_3v30_audit3/`) | PASS: 3 / 3 tokens bit-exact, 0 timing-check violations, 0 SRAM / IO-timing errors, SDF coverage 44,231 / 44,231, 801,252 clk/token, 962 s |
| `flow/power/run_power.sh` (`SKIP_SIM=1`, existing SAIF) | `summary.rpt` byte-identical to the signoff version |
