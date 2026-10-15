# mq_chip on 65 nm GP: pre-layout signoff (phase 2)

This covers Formality, PrimeTime and gate-level simulation of the DC netlists from phase 1
(`synth_results.md`). Everything here is **pre-layout**. Clocks are ideal (no CTS), and
parasitics are DC topographical estimates (no routing). The per-run summaries are in
`results/` (`fm_*.txt`, `sta_*.txt`). Full reports, netlists and SPEF stay on the server
under `~/CME433_TestBench_Fall26/src_int8_tsmc65/build/`.

Tools: Formality Q-2019.12-SP2, PrimeTime Q-2019.12-SP2, VCS S-2021.09-SP1-1, and DC
W-2024.09-SP2 for the netlists.

## 0. Sign-off netlist: `ss_p3.9`

PrimeTime reads the DC estimated parasitics, and on that data it is about 40-60 ps more
pessimistic than DC on the long sequencer -> writeback paths (section 2.3). The ss netlist
that DC synthesised at 4.0 ns therefore misses 4.0 ns in PrimeTime by 41 ps. The sign-off
netlist is instead synthesised at **3.9 ns** (`syn/scripts/run_batch.sh ss:3.9`) and signed
off at **4.0 ns (250 MHz)**. It costs +0.2 % area: 208,697 um^2 and 58,832 cells
(`results/syn_ss_p3.9.txt`). The flow is otherwise unchanged. DC now also writes
`mq_chip.{max,min}.spef` for PrimeTime. Re-running ss/tt/ff at 4 ns and ss at 2.6 / 2.7 ns
gave the same summaries as phase 1.

## 1. Formality (RTL vs netlist)

`lec/run_batch.sh <syn_tag> ...` -> `lec/run_fm.csh` -> `lec/fm_lec.tcl`. The reference is
the RTL that DC read (`rtl_mem/chip65.f`, site ICG wrapper). The implementation is
`mq_chip.v`, with DC's `mq_chip.svf` as guidance. Settings: `synopsys_auto_setup`, and
`verification_clock_gate_hold_mode any` for the clock gates that DC inserted.

| Netlist | Verdict | Passing (Port / DFF / LAT) | Failing | Aborted | Unmatched | SVF guidance accepted / rejected |
|---|---|---|---|---|---|---|
| **ss_p3.9 (sign-off)** | **SUCCEEDED** | 26,389 (53 / 992 / 25,344) | 0 | 0 | 74 impl. (all `LATCG`) | 335 / 0 |
| ss_p4 | SUCCEEDED | 26,389 (53 / 992 / 25,344) | 0 | 0 | 74 impl. (all `LATCG`) | 335 / 0 |
| tt_p4 | SUCCEEDED | 26,389 (53 / 992 / 25,344) | 0 | 0 | 74 impl. (all `LATCG`) | 332 / 0 |
| ff_p4 | SUCCEEDED | 26,389 (53 / 992 / 25,344) | 0 | 0 | 74 impl. (all `LATCG`) | 325 / 0 |

- The 25,344 latch points are the 22,528 RF data latches plus the 2,816 latches inside the
  RTL word clock gates. The 74 unmatched implementation points are the latches of the
  clock gates that DC added with `-gate_clock` (2,890 ICGs - 2,816 RTL word gates).
  Formality verifies them through the clock-gate hold mode.
- Each run takes about 1.5 min. Artefacts: `results/fm_<tag>.txt`, and on the server
  `build/lec/<tag>/` (`fm.log`, `rpt/{status,unmatched,failing,aborted,guidance}.rpt`).

## 2. PrimeTime STA

`sta/run_batch.sh <syn_tag>:<corner>[:<rc>[:<period>]] ...` -> `sta/run_pt.csh` ->
`sta/pt_sta.tcl`. The shared loader `syn/common/pt_load.tcl` does: netlist + one corner
`.db`, the same `syn/constraints/mq65.sdc` that DC compiled against (with the analysis
corner's library for the driving cells and the load), and the DC estimated SPEF. Clocks are
ideal: no `set_propagated_clock` and no CTS. Clock uncertainty is 0.25 ns for setup and
0.05 ns for hold. Libraries: ss 0.9 V 125 C, tt 1.0 V 25 C, ff 1.1 V -40 C. RC: max = that
run's corner (cworst / typical), min = best RC. Each run takes about 15 s.

**Latch handling.** The RF word latches (transparent-high, behind the per-word ICGs) use
PrimeTime's default level-sensitive analysis, with no exceptions in the SDC. The write path
`wd_r` (posedge) -> latch D may borrow up to the closing (falling) edge of the same cycle.
The borrowed time is then charged to the path launched from the latch, which is the RF read
path latch Q -> read mux -> `q_r`. Every latch endpoint reports slack 0 (borrowing), so the
table also lists the worst path into flops / outputs and the latch-out (read) path.
`check_timing` is clean in every run: no unconstrained endpoints, no loops, no missing
clocks or delays.

### 2.1 At 4.0 ns (250 MHz)

| Netlist @ corner (RC) | Setup WNS / TNS (ns), into flops | Violating endpoints | Hold WNS (ns) | Max borrow into latch (ns) | RF read path slack (ns) | RF latch hold slack (ns) |
|---|---|---|---|---|---|---|
| **ss_p3.9 @ ss (max)** | **+0.104 / 0** | 0 | +0.079 | 0.94 | +1.94 | +2.11 |
| **ss_p3.9 @ tt (max)** | **+1.560 / 0** | 0 | +0.031 | 0.69 | +2.68 | +2.05 |
| **ss_p3.9 @ ff (min)** | **+2.350 / 0** | 0 | **+0.0016** | 0.54 | +3.09 | +2.01 |
| ss_p4 @ ss (max) | -0.041 / -1.316 | 103 | +0.071 | 0.94 | +1.97 | +2.12 |
| ss_p4 @ tt (max) | +1.456 / 0 | 0 | +0.027 | 0.68 | +2.69 | +2.05 |
| ss_p4 @ ff (min) | +2.276 / 0 | 0 | +0.0002 | 0.54 | +3.10 | +2.01 |
| tt_p4 @ tt (max) | +0.050 / 0 | 0 | +0.027 | 0.70 | +2.61 | +2.05 |
| ff_p4 @ ff (min) | +0.343 / 0 | 0 | +0.0016 | 0.53 | +3.01 | +2.01 |

- **The sign-off netlist ss_p3.9 meets 4.0 ns at all three corners, setup and hold, under
  ideal clocks.** Hold margins at ff are only 1-2 ps. That is expected before CTS and is
  left for hold fixing after CTS.
- Critical paths at ss: for ss_p3.9 the worst flop path is the lane accumulator
  `u_dp/u_lane/ps_r_reg_1_ -> u_dp/u_lane/acc_reg_31_` (arrival 3.641 ns). For ss_p4 it is
  the sequencer loop counter into the writeback product/output register
  `u_seq/u_loop/pc_reg_7_ -> u_dp/u_wb/y_reg_4_` (arrival 3.806 ns), the same path family
  as in DC. At tt / ff the ss_p3.9 netlist is limited by `pc_reg -> u_mem/u_b/u_odd/u_rf/q_r`.
- RF write: worst `wd_r -> word latch` arrival is 0.69 ns at ss. That is 0.94 ns of
  borrow, counted from the latch opening edge and including the setup and the 0.25 ns
  uncertainty, against the 2.0 ns high phase.
- RF read (the report that phase 1 left empty, now `rpt/timing_rf_rd.rpt` via
  `-through` latch Q pins): worst slack +1.94 ns at ss, with the borrow included.

Artefacts: `results/sta_<syn_tag>_<corner>_<rc>[_at<period>].txt`, and on the server
`build/sta/<same>/` (`pt.log`, `rpt/{timing_max,timing_min,timing_rf_wr,timing_rf_rd,check_timing*,annotated_parasitics,global_timing,violators,disable_timing}.rpt`).
SPEF annotation: 59,089 of 59,176 nets have RC. The 87 without RC are the 85 driverless
(constant) nets, one loadless port net and the root clock net. DC writes no RC for the ideal
clock net, so the `clk` port has a `*PORTS` entry in the SPEF but no `*D_NET`.

### 2.2 Fmax at ss (PrimeTime check of the phase-1 DC sweep)

| DC netlist (target) | PrimeTime setup WNS @ target, ss | Violating endpoints | Closes at (target - WNS) | Hold @ ff (min RC) |
|---|---|---|---|---|
| ss_p2.6 | -0.023 ns (TNS -0.58) | 68 | **2.623 ns (381 MHz)** | -0.0014 ns (1 endpoint, as in DC) |
| ss_p2.7 | -0.016 ns (TNS -0.54) | 51 | 2.716 ns (368 MHz) | +0.0017 ns |

PrimeTime does **not** exactly confirm DC's 2.6 ns (385 MHz): the DC 2.6 ns netlist closes
at **2.62 ns (381 MHz)** in PrimeTime, which is within 1 % of the DC figure. The 2.7 ns
netlist closes at 2.72 ns and is hold-clean. The pre-layout ss Fmax is therefore
**about 2.62 ns / 381 MHz** (PrimeTime). The 4.0 ns sign-off clock is 34 % above that
period. Limiting path at 2.6 ns: `u_seq/u_loop/pc_reg_0_ -> u_dp/u_wb/prod_reg_42_`.

### 2.3 DC / PrimeTime correlation

`sta/pt_corr.tcl` (`MQ65_PT_SCRIPT=pt_corr sta/run_pt.csh ss_p4 ss max`) compares the
worst flop path of ss_p4 at ss: -0.041 ns with the SPEF, and +0.25 ns (CCS) / +0.37 ns
(NLDM-style) with no wire RC. DC reports +0.0001 ns on the same netlist. The gap is in how
the two tools turn the same estimated wire RC into delay (about +60 ps on a 3.8 ns path,
1.6 %). It is not a constraint difference. Synthesising with a 0.1 ns margin (3.9 ns
target) covers it. After layout, StarRC SPEF in PrimeTime replaces both estimates.

## 3. Gate-level simulation (functional check of the netlists)

`sim/gls/run_gls.csh <syn_tag> <vec_name> [timescale] [saif_tok]` runs the **unchanged**
`src_int8` chip TB (`tb_mq_chip.sv`: pad-level QSPI host, golden logits and state images)
on the DC netlist with the library cell models, using VCS with zero delay (`+delay_mode_zero
+nospecify +notimingcheck`). `-override_timescale=100ps/1ps` runs the TB's `#20` half
period as a 4 ns clock (250 MHz). Vectors are cut by `sim/gls/make_vec.sh` and copied by
`sync.sh vec`.

| Netlist | Tokens | Result | clk / token (START -> done, + status / read-back) | VCS CPU |
|---|---|---|---|---|
| **ss_p3.9 (sign-off)** | 31 | **PASS**: 31 x 128 logits bit-exact, 2 state resets, 2 state read-backs (0 / 3,520 mismatching bytes) | 450,412 / 455,312 | 523 s |
| tt_p4 (power netlist) | 31 | **PASS**: same | 450,412 / 455,312 | 538 s |
| tt_p4 | 2 | PASS (1 reset, 1 read-back) | 450,412 / 455,312 | 41 s |

Zero-delay ordering at the latch RF and the clock gates (a known pitfall) does not show up:
every logit and state byte is bit-exact, and the cycle counts are identical to the RTL. Artefacts: on the server
`build/gls/<syn_tag>_<vec>[_t<tok>]/` (`compile.log`, `tb.log`, `mq_chip.saif`).

## 4. What is still open (post-layout)

- CTS: the root clock net drives 2,967 leaf input pins (2,890 of them ICG clock pins), with
  ideal timing here. Hold fixing (ff margins are 1-2 ps) and propagated-clock STA come after
  CTS.
- Routed parasitics (StarRC) and OCV / derates replace the DC estimates and the flat 0.25 ns
  uncertainty.
- Timing GLS with SDF after layout. The zero-delay GLS above only checks function.
