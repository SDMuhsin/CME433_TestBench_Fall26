# mq_chip on 65 nm GP: RTL verification and DC synthesis (phase 1)

mq_chip (`src_int8/`, results in `src_int8/docs/results.md`) is ported to a 65 nm GP
standard-cell library. The eleven 256 x 8 GF180 SRAM macros are replaced by latch register
files (`rtl_mem/`); the rest of the RTL is `src_int8/rtl` unchanged. All numbers below are
pre-layout (ideal clocks, no CTS, no routing). Kit, library and cell names are kept in the
git-ignored `site/` config, see `site/README.md`.

## 1. RTL verification

| Test | Setup | Result | Artefact |
|---|---|---|---|
| RF unit test | `sim/unit/run_rf_unit.sh`: `mq65_latch_rf` vs the GF180 macro model in lock-step, random ce/we/addr incl. read/write collisions | PASS, 200k cycles, 0 mismatches | `sim/build/unit/tb_rf.log` |
| Full chip, 31 tokens | `sim/chip/run_chip_rf.sh` (Verilator 5): the unchanged src_int8 chip TB (pad-level QSPI host) on `rtl_mem/chip65.f`, golden vectors from `src_int8.golden.vectors --chip-only` | **PASS**: 31/31 tokens x 128 logits bit-exact, 2 state resets, 2 state read-backs (0 / 3520 mismatching bytes each), **450,412 clk/token START->done** (455,312 incl. status + read-back), same as the src_int8 RTL reference | `sim/build/chip/tb_mq_chip.log` (63 min wall) |

No RTL bug was found; `src_int8/` is unchanged.

## 2. DC synthesis

Flow: `syn/scripts/run_batch.sh <corner>:<period> ...` -> `run_dc.csh` -> `dc_syn.tcl`
(constraints `syn/constraints/mq65.sdc`, summary writer `syn/common/summary.tcl`).

- Tool: Design Compiler W-2024.09-SP2, **topographical mode** (kit Milkyway frame view,
  9-metal techfile, TLU+ RC: worst for ss, typical for tt, best for ff; min RC best).
- `compile_ultra -no_autoungroup -gate_clock` (+ `-incremental` below 10 ns), no retiming,
  hold fixing against the ff library (`set_min_library`, none in the ff run).
- One synthesis per corner, each with that corner's library as target:
  ss = slow 0.9 V 125 C, tt = typical 1.0 V 25 C, ff = fast 1.1 V -40 C.
- SDC: clock uncertainty 0.25 / 0.05 ns (setup / hold), clock transition 0.15 ns, IO delays
  20 % of the period, max transition min(0.5, 0.1 P) ns, max fanout 16.
- Latch RF write path: wd_r (posedge flop) -> word latch (open in the same high phase) uses the
  tool's default flop-to-latch relationship with time borrowing. Latch endpoints that borrow
  report slack exactly 0, so the table also gives the worst path into flops / outputs.
- Runtime about 5 min per run on 8 cores.
- Each run writes `mq_chip.v`, `mq_chip.sdc`, `mq_chip.ddc` and `mq_chip.svf` (for Formality /
  PrimeTime, phase 2). These stay on the server in
  `~/CME433_TestBench_Fall26/src_int8_tsmc65/build/syn/<corner>_p<period>/`. Reports are in
  `rpt/` there. Summaries are copied to `build/summary/syn_<tag>.txt` and, without
  library names, to `results/syn_<tag>.txt` in this repo.

### 2.1 Per corner at 4.0 ns (250 MHz)

4 ns is the target clock: ss meets it with 35 % margin over the pre-layout Fmax (2.6 ns),
to leave room for CTS, routing and OCV.

| | ss | tt | ff |
|---|---|---|---|
| Total cell area (um^2) | 208,301 | 206,970 | 206,352 |
| NAND2 gate equivalents | 144,654 | 143,729 | 143,300 |
| Leaf cells | 58,866 | 58,219 | 57,195 |
| Combinational area / cells | 69,016 / 32,456 | 67,701 / 31,809 | 67,090 / 30,785 |
| Flip-flop area / cells | 7,017 / 992 | 7,001 / 992 | 6,994 / 992 |
| Latch area / cells (all in the RF) | 113,541 / 22,528 | 113,541 / 22,528 | 113,541 / 22,528 |
| ICG area / cells (RF: 2,846, incl. 2,816 word gates) | 18,727 / 2,890 | 18,727 / 2,890 | 18,727 / 2,890 |
| Latch RF total (11 x 256 x 8), share of area | 153,345 (73.6 %) | 153,010 (73.9 %) | 153,116 (74.2 %) |
| Setup WNS / TNS (ns) | 0.000 / 0.000 | 0.000 / 0.000 | 0.000 / 0.000 |
| Worst path into flops / outputs, slack (ns) | +0.0001 | +0.061 | +0.291 |
| Hold WNS / TNS (ns, ideal clock) | +0.0002 / 0 | -0.0000 / 0 | +0.0017 / 0 |
| Leakage (DC, library) | 1.10 mW | 0.79 mW | 1.73 mW |
| Dynamic (DC, default activity only) | 4.69 mW | 6.04 mW | 9.17 mW |

- Critical path, all corners: the sequencer loop counter (`u_core/u_seq/u_loop/pc_reg_*`)
  -> datapath writeback product register (`u_core/u_dp/u_wb/prod_reg_*`). At ff it ends at
  `u_wb/y_reg_*`. The worst RF write path (`u_rf/wd_r_reg` -> word latch, 0.6-0.7 ns) has
  ample margin within the half cycle.
- The dynamic figures come from DC's default switching activity: they are not a workload
  estimate (that is phase 2, with SAIF from simulation). Leakage is the library value at
  each corner's PVT.
- Breakdown in the ss run, leaf area (um^2): RF in `u_mem` 187,909 (HMEM 153,585, BMEM
  34,193); datapath 8,311 (mul24x17 3,567, wb 3,121, lane 1,481); sequencer 5,768 (ucode ROM
  1,354); NLU 2,520 (ROM 1,331); stream FIFO 2,280; host 1,191; CSR 133.
- Within the RF (ss): latches 113,541, word ICGs 18,442, decode / read-mux logic 54,817,
  flops (wd_r, q_r) 2,101 um^2.

Artefacts: `results/syn_{ss,tt,ff}_p4.txt`, server `build/syn/{ss,tt,ff}_p4/`
(`summary.txt`, `rpt/qor.rpt`, `rpt/area.rpt`, `rpt/power_default.rpt`, `rpt/timing_max.rpt`).

### 2.2 Fmax sweep at ss

| Period (ns) | Area (um^2) | Cells | Setup WNS (ns) | Setup TNS (ns) | Hold WNS (ns) |
|---|---|---|---|---|---|
| 5.0 | 207,795 | 58,558 | 0.000 | 0.000 | +0.001 |
| 4.0 | 208,301 | 58,866 | 0.000 | 0.000 | +0.0002 |
| 3.0 | 212,768 | 60,184 | 0.000 | 0.000 | -0.0007 (1 endpoint) |
| 2.8 | 214,096 | 60,348 | 0.000 | 0.000 | +0.0014 |
| 2.7 | 216,181 | 60,859 | 0.000 | 0.000 | +0.0019 |
| **2.6** | 220,127 | 61,247 | **0.000** | 0.000 | -0.0014 (1 endpoint) |
| 2.5 | 220,712 | 60,950 | -0.023 | -1.22 (98 endpoints) | +0.0013 |
| 2.2 | 222,609 | 61,439 | -0.331 | -685 | -0.0000 |
| 2.0 | 223,887 | 62,189 | -0.454 | -957 | +0.0004 |

**Pre-layout Fmax at ss: 2.6 ns (385 MHz), setup slack >= 0.** 2.7 ns is the tightest
period that is also hold-clean. The -1 ps hold misses at 3.0 and 2.6 ns are single
endpoints under ideal clocks and are left for post-CTS hold fixing.
The limiting path at 2.5 ns: `u_seq/u_loop/pc_reg_3_` -> `u_dp/u_wb/prod_reg_36_`.
At 250 MHz, 450,412 clk/token is 1.80 ms/token, against 18.0 ms on the GF180 chip at 25 MHz.

Artefacts: `results/syn_ss_p*.txt`, server `build/syn/ss_p*/`. The 5.0 ns run used an
earlier summary format, which lacks the cell-class breakdown.

## 3. Phase 2

Formality, PrimeTime, gate-level simulation and SAIF power are in `signoff_pre_layout.md`
and `power_pre_layout.md`. PrimeTime with the DC estimated SPEF is about 40-60 ps more
pessimistic than DC at ss. The sign-off netlist is therefore synthesised at 3.9 ns
(`results/syn_ss_p3.9.txt`, 208,697 um^2) and signed off at 4.0 ns. PrimeTime puts the
ss pre-layout Fmax at about 2.62 ns (381 MHz), against DC's 2.6 ns.
