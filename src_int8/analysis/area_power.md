# mq_chip (INT8) vs mb_chip (FP16): why the INT8 chip is larger and hotter

Analysis only (2026-10-14); no RTL or flow change. **Decision: none of the recommendations in section 3 is acted on
for this tapeout; `mq_final` is the signed-off design as is (`docs/signoff.md`, `docs/results.md` section 9).** Artefacts: `flow/runs/mq_final` vs `src/flow/runs/mb_final`
(step `*.nl.v`, `or_metrics_out.json`, logs), `flow/build/power/*` (SAIF, OpenSTA reports, nom_tt), `syn/build/*.stat`.
Scripts and derived tables: `analysis/area/*.py`, `analysis/power/*`, `analysis/data/*.txt` (see `analysis/README.md`).

## 1. Area: the gap is made at synthesis, not in PnR

| std-cell area, um^2 | INT8 mq | FP16 mb | delta | source |
|---|---|---|---|---|
| Yosys synthesis (flow, `SYNTH_MUL_BOOTH: false`) | 229,903 | 163,057 | **+66,846** | 13-floorplan `design__instance__area__stdcell` |
| + tap/endcap (6,839 / 7,249 x 4.39) | +30,026 | +31,826 | -1,800 | step 19 |
| + repair_design post-GPL (fanout/slew/cap/wire) | +30,935 | +22,716 | +8,219 | step 32 (1,879 / 1,299 buffers) |
| + CTS (374 / 294 cells) | +16,016 | +12,721 | +3,295 | step 35 |
| + hold buffers (244 / 280) | +5,892 | +6,762 | -870 | step 37 |
| + repair post-GRT (92 / 61 buffers) | +1,355 | +856 | +499 | step 41 |
| + antenna diodes in DRT (2,239 / 1,395 x 4.39) | +9,830 | +6,124 | +3,706 | step 45 |
| **final** | **323,957** | **244,062** | **+79,895** | 45-detailedrouting |

PnR overhead is 94.1k (1.41x synth) vs 81.0k (1.50x): per unit of logic INT8 is *not* worse in PnR; 84 % of the
79.9k gap (66.8k) is RTL/synthesis. Per hierarchy (`area/hier_attrib.py`, forward-trace of flattened cells to named nets,
`data/mq_synth.txt`, `data/mb_synth.txt`):

| unit | INT8 um^2 (flops) | FP16 um^2 (flops) | delta |
|---|---|---|---|
| datapath: u_dp = u_mul 24x17 + u_lane + u_wb (INT8) / u_lane (FP16) | 104,474 (213) | 50,257 (144) | **+54,217** |
| sequencer u_seq + u_rf + u_loop (ucode ROM 53 b x 221 vs 36 b x 201; regfile 112 vs 80 flops) | 70,598 (296) | 56,412 (218) | +14,186 |
| NLU | 11,944 | 17,083 | -5,139 |
| FIFO (16 x 8, 152 flops) / host / CSR / arbiter / mem glue | 37,150 | 36,220 | +930 |
| flops total | 803 | 672 | +131 |

Two concrete synthesis causes: (a) the **flow synthesises the multiplier as a plain array**: `SYNTH_MUL_BOOTH` is
`false` (default) and the yosys log has no booth pass, while `syn/synth_chip.sh` uses `-booth` and measures 213,946 um^2
for the same RTL (`mq_mul24x16` 51,311 -> `mq_mul24x17` Booth 36,803, `syn/build/*.stat`): **~15k um^2 lost to a
config default**; (b) the INT8 write-back `mq_wb` (50.3k, 136 flops) is a full second datapath (49-bit requant, shifter,
saturate) that FP16 does not have (`mb_fp32_wb` 2.4k).

**What the repair step buffers** (`area/repair_nets.py`, `data/repair_mq.txt`): the macro buses. `u_core.s_wdata` (24 b to
all 11 SRAM D pins): 127 wire + 40 fanout buffers and 332 diodes; `u_core.m_addr` (9 b x 11 macros): 61 wire +
38 max_cap + 87 diodes; SRAM `rdata` nets ~140 diodes + 30 wire buffers; control fan-outs `u_seq.pc` (61 fanout +
20 max_cap), `u_fifo.rp` (30 + 12), `l_issue` (10 + 9). FP16 has the same pattern with smaller numbers (s_wdata 107 wire
/ 319 diodes, m_addr 61 / 134). The 2,239 diodes are all DRT antenna repair (`DRT_ANTENNA_REPAIR_ITERS: 3`, identical in
both configs; `DIODE_ON_PORTS: in` gives only the 16 port buffers); they scale with routed length: 973.5 mm vs 673.6 mm
(+44.5 % for +21.6 % cells, 47.2 vs 39.7 um/cell) because 11 macros occupy the whole east/centre and every macro bus
bit spans three rows. Config diff (`data/config_diff.txt`): the *only* numeric difference is
`GRT_DESIGN_REPAIR_MAX_SLEW_PCT` 40 vs 30 (needed: run mq_r0 at 30 % left a 1.52 ns slew at max_ss), plus the 11th macro
and the RTL list; floorplan, PDN, tap distance (20 um), CTS (`clkbuff_12`, cluster 12), antenna and diode settings are
identical. Utilisation 65.6 % vs 56.5 % is 745k vs 678k of macro plus the 80k std-cell delta on the same core
(1,642,850 um^2); std-cell-only utilisation is 36.6 %: not congested, no floorplan problem.

## 2. Power (nom_tt, SAIF from SDF GLS, `data/pow_*.txt`, `data/tog_*.txt`)

| mW | INT8 | FP16 | note |
|---|---|---|---|
| Clock | 17.14 | 13.89 | 374 vs 294 CTS cells; 814 vs 682 sinks -> 21.1 vs 20.4 uW/sink. 256 clkbuff_12 = 16.6 mW |
| Combinational | 8.51 | 1.99 | zero-delay 5.08 vs 1.47: **glitch +3.43 mW** (lane x2.16, wb x1.68 toggles vs zero-delay) |
| of which repair buffers | 3.10 | 0.75 | wire 1.50, fanout 0.90, max_cap 0.70 (s_wdata wire chain alone 0.29 mW) |
| SRAM | 2.17 | 2.27 | BMEM even/odd 0.96 each; HMEM x9 0.25 |
| Total / energy per token | 27.9 / 503 uJ | 18.2 / 583 uJ | 455k vs 806k cycles: INT8 is 14 % better per token |

Top combinational consumers (logic + its repair buffers): `u_dp.u_lane` 3.48 mW (0.95 of it buffers; zero-delay 1.57),
`u_dp.u_wb` 1.78 (zd 0.89), `u_seq` 1.33, `u_dp` operand muxes 0.33, `u_nlu` 0.18, `u_fifo` 0.20, `u_rf` 0.17.
Mechanism: `mq_dp.v` feeds the shared 24x17 array through combinational muxes `issue ? a : ma` / `issue ? b : mb`;
`ma`/`mb` are `acc`/`me` slices from `mq_wb`, so the ~1,900-cell multiplier re-evaluates on every `l_a`/`l_b`
(0.060 toggles/bit/cycle), `acc`, `ph` or `me` change although `l_issue` is high only 12.3 % of cycles, and its
outputs glitch into `p_r`, the lane adder and the wb path. Lane cell outputs toggle 0.198/cycle (FP16 lane 0.095);
array multipliers glitch far more than Booth. Per cycle INT8 simply does ~2x the work (1.77x fewer cycles).
Clock: per sink the two trees cost the same; INT8 has +131 flops and the 11th SRAM. The library has **no clock-gating
cell** (`gf180mcu_as_sc_mcu7t3v3` has only `dlxtp/dlxtn` latches) and neither RTL gates clocks, so every flop and all
11 SRAM `CLK` pins (0.294 pF each = 3.2 pF, vs 803 x 5.2 fF = 4.1 pF of flop CK) toggle every cycle while `CEN` is
inactive 98.8 % of the time: the three leaf buffers that drive only SRAM clocks cost 2.03 mW. Clock power by block:
FIFO 3.00 mW (150 flops), u_seq 2.66, u_rf 2.15, u_wb 2.00, u_mem clocks 2.38, host 2.33, lane 0.87.
Flop CK internal power is absent from the lib (sequential internal = 0); the proxy adds 4.7 mW of flop internal power
but lowers the clock-net switching by 1.0 mW (the proxy flops have a smaller CK pin cap), so the total goes 27.9 -> 31.6 mW
(+3.7 mW, `flow/build/power/summary.rpt`, `saif_proxy` rows).

## 3. Recommendations (savings vs 323,957 um^2 / 27.9 mW; bit-exact = same logits)

| # | change | est. saving | bit-exact / cycles | risk |
|---|---|---|---|---|
| 1 | `SYNTH_MUL_BOOTH: true` in `flow/config.yaml` (what `syn/` already does) | -14.5k synth -> **~-18k um^2** placed; -0.8..-1.2 mW (fewer adders, fewer glitch paths) | yes / same | low: re-run flow + GLS; one line |
| 2 | Operand isolation on the multiplier: register `a`,`b` (41 flops, +2.4k um^2) loaded only on `issue`, and hold `ma`/`mb` (`mq_wb`) except in the wb phases that multiply; or AND-gate the mux outputs with `issue | wb_mul` | **-1.5..-2.5 mW** (kills idle re-evaluation and most of the +3.4 mW glitch in lane/wb) | yes / registered variant +1 cycle per issue unless folded into the existing `p_r` stage; AND-gate variant: same cycles | medium: critical path is seq -> mux -> mul -> p_r (24.9 ns of 40), 14 ns slack covers one extra gate |
| 3 | Latch-based clock gating (`dlxtn` + `and2`, SDC `set_clock_gating_check`) on FIFO (3.0 mW, one entry written per cycle), regfile (2.15), wb (2.0), host sync/CSR (2.3); gate SRAM `CLK` with `CEN` (2.0 mW) | **-4..-6 mW** of 17.1 (leaf buffers + CK pins; trunk stays) | yes / same | medium-high: hand-built ICG must be glitch-free, hold on enable paths, CTS sees gates as sinks; SRAM gating needs the macro's hold-of-Q behaviour confirmed |
| 4 | CTS tuning: `CTS_SINK_CLUSTERING_SIZE` 12 -> 24..32, leaf buffers `clkbuff_4/8` (keep `clkbuff_12` root) | -3..-4 mW (internal 11.3 mW of the tree scales with buffer count/size; switching 5.8 mW stays), -6..-8k um^2 | yes / same | low-medium: skew 0.54 ns and 244 hold buffers will move; setup slack 14 ns |
| 5 | Pipeline the macro buses per SRAM row (3 local copies of `s_wdata`/`m_addr` or a write-data register at the arbiter) | -266 buffers (-3.5k um^2), -420 diodes (-1.8k), -0.5 mW | yes / +1 cycle on SRAM writes unless absorbed in `mq_mem_arb` | medium; low value |
| 6 | `FP_TAPCELL_DIST` 20 -> 30 um if the gf180 latch-up rule allows | -10k um^2 of tap (30.0k today, 9.3 % of std cells; no power) | yes / same | needs PDK/DRC confirmation; does not shrink die |
| 7 | Keep `GRT_DESIGN_REPAIR_MAX_SLEW_PCT: 40`, antenna settings, floorplan: they are not the cause (diff shows nothing else differs) | 0 | - | - |
| 8 | Longer term: fold `mq_wb` requant (50k um^2, 136 flops) into the lane pipeline / narrow the 49-bit path; shrink ucode ROM (53 b x 221 -> packed fields) | -20..-30k um^2, -1..-2 mW | needs re-verification | high effort |

Expected after 1+2+3+4: ~290k um^2 (below FP16's 244k only with 6+8) and ~17..19 mW, i.e. **~310..350 uJ/token**
(FP16 583). Items 1 and 4 are config-only and should be tried first; item 2 is the only RTL change with a cycle-count
caveat; item 3 is the biggest lever but the one with real timing/CTS risk on this library.
