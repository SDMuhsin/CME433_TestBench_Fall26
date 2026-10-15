# mq_chip on 65 nm GP: results (GF180 tape-out vs 65 nm pre-layout vs 65 nm post-layout)

The INT8 Mamba accelerator `mq_chip` (`src_int8/`, GF180 results in `src_int8/docs/results.md`) ported to a
commercial 65 nm GP standard-cell flow: DC (topographical) -> Formality -> ICC2 place and route -> StarRC ->
PrimeTime / PrimeTime PX -> VCS gate-level simulation -> Calibre DRC / antenna / LVS. The 11 GF180 SRAM macros are
replaced by latch register files (`rtl_mem/`, 11 x 256 x 8 b), so the 65 nm block is standard cells only.

**Scope.** The 65 nm block is **core only: no pad ring, no seal ring, no dummy fill** (die = core + 12 um margin).
Pre-layout = DC netlist, ideal clocks, DC-estimated RC (`signoff_pre_layout.md`, `power_pre_layout.md`). Post-layout =
the routed block `ss_p3.9` (DC netlist synthesised at 3.9 ns, laid out and signed off at 4.0 ns / 250 MHz),
propagated clocks, extracted RC. Summaries cited as `results/<file>` are in `src_int8_tsmc65/results/` (copied from the
server by `sync.sh pull`); full reports, netlists, SPEF, SAIF and GDS stay on the server under `build/`.

**RC corners.** The kit's StarRC model is **typical only** (and is for a metal stack whose top metal differs from the
layout's; the top metal carries only the power mesh). Sign-off parasitics are therefore: **ss = ICC2 extraction with the
worst-RC TLU+ model, ff = ICC2 extraction with the best-RC model, tt = StarRC typical**. StarRC typical at ss / ff and
ICC2 typical at tt are run as labelled cross-checks (StarRC vs ICC2 at tt agree within 50 ps on setup, 2 ps on hold).

## 1. Summary table

| Metric | GF180 tape-out (`src_int8`) | 65 nm pre-layout (DC netlist) | **65 nm post-layout (routed)** |
|---|---|---|---|
| Die / core | 1.859 / 1.631 mm^2 (1675 x 1110 um slot, incl. pad ring) [GF s.3] | - (no floorplan) | **0.348 / 0.320 mm^2** (590.6 x 589.2 / 566.6 x 565.2 um, core only) [`results/pnr_ss_p3.9.txt`] |
| Memory | 11 SRAM macros, 745,485 um^2 [GF s.3] | 11 latch RFs: 22,528 latches + 2,846 ICGs, 153,550 um^2 (73.6 %) [`results/syn_ss_p3.9.txt`] | same RFs, all clock gates kept |
| Std cells (excl. fill) | 20,625 incl. 6,839 tap / endcap [GF s.3] | 58,832 [`results/syn_ss_p3.9.txt`] | **57,047** + 72,793 filler [`results/pnr_ss_p3.9.txt`] |
| Std-cell area | 323,957 um^2 [GF s.3] | 208,697 um^2 [`results/syn_ss_p3.9.txt`] | **208,251 um^2** [`results/pnr_ss_p3.9.txt`] |
| Utilisation | 65.6 % incl. macros (36.6 % std cells) [GF s.3] | - | **65.0 %** of core [`results/pnr_ss_p3.9.txt`] |
| Clock network | 285 CTS buffers + 89 inverters, no clock gating [GF s.3, s.5] | ideal | 2,890 ICGs + 246 CTS buffers / inverters, 26,410 sinks [`results/stapost_ss_p3.9_ss_icc2_ss.txt`] |
| Routed wire | 973.5 mm [GF s.3] | - | 1,206.5 mm, 0 antenna diodes [`results/pnr_ss_p3.9.txt`] |
| Sign-off clock | 40 ns (25 MHz) | 4.0 ns (250 MHz) | 4.0 ns (250 MHz) |
| Fmax at ss | ~38.6 MHz implied by +14.11 ns max_ss slack at 40 ns (not swept) [GF s.4] | 257 MHz for this netlist (4.0 - 0.104 ns); 381 MHz for the 2.6 ns DC netlist [`signoff_pre_layout.md` s.2] | **251 MHz** (closes at 3.982 ns, section 3) [`results/stapost_ss_p3.9_ss_icc2_ss_pt_fmax.txt`] |
| Worst setup slack, ss | +14.11 ns (max_ss) [GF s.4] | +0.104 ns [`results/sta_ss_p3.9_ss_max_at4.txt`] | **+0.018 ns** (worst RC) [`results/stapost_ss_p3.9_ss_icc2_ss.txt`] |
| Worst hold slack, ff | +0.106 ns (min_ff) [GF s.4] | +0.0016 ns (ideal clocks) [`results/sta_ss_p3.9_ff_min_at4.txt`] | **+0.027 ns** (best RC) [`results/stapost_ss_p3.9_ff_icc2_ff.txt`] |
| Clock skew (global) | 0.54 / -0.57 ns setup / hold [GF s.4] | 0 (ideal) | 0.523 ns ss, 0.343 ns tt, 0.242 ns ff [`results/stapost_*`] |
| Power, nominal / tt | 27.89 mW at 25 MHz, 3.3 V [GF s.5] | 7.39 mW at 250 MHz, 1.0 V [`power_pre_layout.md`] | **10.61 mW at 250 MHz**, 1.83 mW at 25 MHz [`results/pwrpost_*`] |
| Energy / token, 25 MHz | **503 uJ** [GF s.5] | 26.7 uJ [`power_pre_layout.md`] | **33.4 uJ** |
| Energy / token, 250 MHz | - | 13.5 uJ [`power_pre_layout.md`] | **19.3 uJ** |
| Equivalence | - (open-source flow) | Formality RTL vs netlist SUCCEEDED [`results/fm_ss_p3.9.txt`] | **Formality netlist vs routed netlist SUCCEEDED** [`results/fm_post_ss_p3.9.txt`] |
| Gate-level sim | SDF GLS 31 tokens, 3 corners PASS [GF s.4] | 31 tokens bit-exact [`signoff_pre_layout.md` s.3] | **31 tokens bit-exact** (routed netlist) |
| DRC / antenna | clean (filled GDS: 2 density items) [GF s.6] | - | **0 / 0**, plus 12 low-density results (no dummy fill) [`results/drc_*`] |
| LVS | Netgen match [GF s.6] | - | **Calibre: INCORRECT (open, section 6)**; ICC2 connectivity check 0 [`results/lvs_ss_p3.9.txt`] |

[GF s.n] = section n of `src_int8/docs/results.md`. Energy / token = average power x 1.821 ms (250 MHz) or 18.21 ms
(25 MHz), the token window (START -> end of logit read-back) of the SAIF.

## 2. Post-layout STA (PrimeTime, 4.0 ns, propagated clocks, plain sign-off SDC)

Run by `signoff/run_post_layout.sh ss_p3.9 sta` (`sta/post/run_pt_post.csh <tag> <corner> <rc>`). Sign-off SDC
unchanged from synthesis: 0.25 / 0.05 ns setup / hold uncertainty, IO delays 20 % of the period.

| Corner / RC | Setup into flops (ns) | Latch D (borrow, ns) | RF read path (ns) | Hold (ns) | Latch hold (ns) | Latency min-max / skew (ns) | Summary |
|---|---|---|---|---|---|---|---|
| **ss 0.9 V 125 C / worst RC (sign-off)** | **+0.018** | 0 (1.82 borrowed) | +1.50 | +0.119 | +1.96 | 0.212-0.735 / 0.523 | `stapost_ss_p3.9_ss_icc2_ss.txt` |
| ss / StarRC typical (cross-check) | +0.180 | 0 (1.69) | +1.67 | +0.145 | +1.96 | 0.188-0.679 / 0.491 | `stapost_ss_p3.9_ss_star.txt` |
| **tt 1.0 V 25 C / StarRC typical (sign-off)** | **+1.547** | 0 (1.17) | +2.48 | +0.073 | +1.95 | 0.125-0.456 / 0.331 | `stapost_ss_p3.9_tt_star.txt` |
| tt / ICC2 typical (cross-check) | +1.500 | 0 (1.20) | +2.44 | +0.075 | +1.95 | 0.135-0.478 / 0.343 | `stapost_ss_p3.9_tt_icc2_tt.txt` |
| **ff 1.1 V -40 C / best RC (hold sign-off)** | +2.222 | 0 (0.88) | +2.90 | **+0.027** | +1.94 | 0.091-0.333 / 0.242 | `stapost_ss_p3.9_ff_icc2_ff.txt` |
| ff / StarRC typical (cross-check) | +2.226 | 0 (0.87) | +2.90 | +0.027 | +1.94 | 0.089-0.329 / 0.241 | `stapost_ss_p3.9_ff_star.txt` |

- 0 setup and 0 hold violations in all six runs; `check_timing` clean; all 26,410 clock sinks timed. The RF write
  path borrows into the transparent-high word latches (slack 0 by construction); the borrowed time is charged to the
  read path, which keeps >= 1.50 ns. Worst flop path at ss: sequencer loop counter -> writeback output register.
- Design-rule constraints: 0 max-transition and 0 max-capacitance violations. **max_fanout (limit 16): 5 nets at
  fanout 17** (high-fanout buffers in the memory address decode). The first layouts had 2,256 such nets because the
  P&R optimiser ignores the SDC fanout limit; its own fanout limits are now set to 16 (`syn/common/pnr_common.tcl`,
  `MQ65_PNR_MAX_FANOUT`). The 5 remaining overshoots by one load are accepted: fanout is a proxy for slew / cap, which
  are clean, and their timing is included in the slacks above.
- ICC2 optimises with extra margins (setup +0.15 ns, hold +0.03 ns, max transition 0.30 ns data / 0.20 ns clock;
  `pnr_common.tcl`): without them the first layout closed in ICC2 (-5 ps) but missed by -131 ps in PrimeTime, with 9.5k
  max-transition violations (PrimeTime data paths ~160 ps slower). With the margins ICC2 reports -5 ps at ss
  (`results/pnr_ss_p3.9.txt`) and PrimeTime +18 ps with the plain SDC.

## 3. Post-layout Fmax at ss (worst RC), no re-layout

`MQ65_PT_SCRIPT=pt_fmax sta/post/run_pt_post.csh ss_p3.9 ss icc2_ss` re-times the same layout at each period
(`results/stapost_ss_p3.9_ss_icc2_ss_pt_fmax.txt`):

| Period (ns) | 4.2 | 4.1 | 4.0 | 3.95 | 3.9 | 3.85 | 3.8 | 3.7 |
|---|---|---|---|---|---|---|---|---|
| Setup WNS (ns) | 0 | 0 | 0 | -0.032 | -0.082 | -0.132 | -0.182 | -0.282 |
| Violating endpoints | 0 | 0 | 0 | 36 | 89 | 432 | 1,096 | 2,142 |
| Hold WNS (ns) | +0.150 | +0.139 | +0.119 | +0.109 | +0.099 | +0.089 | +0.079 | +0.059 |

Slack falls 1:1 with the period below 4.0 ns (+0.018 ns at 4.0 into flops), so the layout closes at **3.982 ns =
251 MHz** at ss / worst RC. (Hold changes only because the input delay is 20 % of the period.) The pre-layout 381 MHz
belongs to a different, 2.6 ns DC netlist; this one was synthesised for 4.0 ns.

## 4. Post-layout power (PrimeTime PX, tt 1.0 V 25 C, StarRC typical, propagated clocks)

Activity: SAIF of token 1 from the zero-delay GLS of the routed netlist, 100 % of nets and cells annotated
(`power/post/run_power_post.csh`; `results/pwrpost_ss_p3.9_post_ss_p3.9_tok31_tt_p4.txt`, `..._tok2_tt_p40.txt`).

| | Pre-layout 250 MHz [`power_pre_layout.md`] | **Post-layout 250 MHz** | **Post-layout 25 MHz** |
|---|---|---|---|
| Cell internal | 6.314 mW | 6.411 mW | 0.641 mW |
| Net switching | 0.269 mW | 3.344 mW | 0.334 mW |
| Leakage | 0.810 mW | 0.859 mW | 0.859 mW |
| **Total** | **7.393 mW** | **10.614 mW** | **1.834 mW** |
| clock_network group | 6.190 mW (83.7 %), root net excluded | 9.306 mW (87.7 %), incl. clock tree | 1.007 mW (54.9 %) |
| register / combinational | 0.569 / 0.635 mW | 0.565 / 0.743 mW | 0.497 / 0.330 mW |
| By block | RFs 6.48 mW | RFs 6.42 mW (HMEM 5.23, BMEM 1.16), datapath 0.45, sequencer 0.22, host 0.12, FIFO 0.10 mW | - |
| **Energy / token** | 13.5 uJ (26.7 uJ at 25 MHz) | **19.3 uJ** | **33.4 uJ** (15.6 uJ of it leakage) |

The rise over pre-layout is the clock tree (net switching +3.1 mW, mostly the clock nets to the 2,890 clock gates,
which pre-layout were ideal and unannotated). Against GF180 (503 uJ / token at 25 MHz) the 65 nm block uses
**15x less energy per token at the same 25 MHz clock** and is signed off at a 10x faster clock; both figures exclude IO power.

## 5. Verification of the routed block

| Check | Result | Artefact |
|---|---|---|
| Formality, DC netlist (reference) vs routed netlist, with the P&R guidance files | **SUCCEEDED**: 26,389 passing (53 port, 992 DFF, 25,344 latch), 0 failing / aborted / unmatched; guidance 8 accepted, 0 rejected | `results/fm_post_ss_p3.9.txt`, `lec/fm_lec.tcl` |
| Gate-level sim (VCS, zero delay), routed netlist, 4 ns clock | **PASS**: 31 tokens x 128 logits bit-exact, 2 state resets, 2 state read-backs (0 / 3,520 bytes); 450,412 clk / token | server `build/gls/post_ss_p3.9_tok31/tb.log` |
| Same, 40 ns clock (power SAIF) | PASS: 2 tokens bit-exact, 1 reset, 1 read-back | `build/gls/post_ss_p3.9_tok2/tb.log` |
| ICC2 route / connectivity checks | 0 DRC, 0 antenna, 0 open, 0 short, 0 floating PG, legality 0 | `results/pnr_ss_p3.9.txt` |
| Calibre DRC, main deck of the layout's metal stack (action-required rules) | **0** results except **12 low-density (DN.1) windows on M2-M9**: the block has no dummy fill, which is added at chip assembly | `results/drc_ss_p3.9_MQ65_DRC_DECK.txt` |
| Calibre antenna | **0** | `results/drc_ss_p3.9_MQ65_ANT_DECK.txt` |
| Calibre LVS (hierarchical, library cells matched by name) | **INCORRECT** - open, section 6 | `results/lvs_ss_p3.9.txt` |

**How Formality passes.** No black-box, don't-verify, user-match or register-merge settings are used; only
`synopsys_auto_setup` and the clock-gate hold mode (for the DC-inserted gates) as in the RTL check. The first layout
let placement merge equivalent clock gates across hierarchy (1,338 instead of 2,890 gates: e.g. the word gates of the
three byte RFs of an HMEM triple). Formality Q-2019.12 rejects that merge guidance ("non-unique parent design for
merged cells", 778 of 778), so the 12,288 word latches behind the merged gates failed. Clock-gate merging is
therefore **disabled in placement** (`pnr/place/place.tcl`) and the block was re-laid out; every state point now
matches one to one and all STA / power / GLS / DRC numbers here are from that layout.

## 6. Open items and headroom (honest list)

1. **Calibre LVS is not clean.** All 182 library cells compare CORRECT and all 57,167 top-level instances match, but
   the top cell is INCORRECT: 151 nets reported (each source net paired with two layout nets of the same total
   connections, in the writeback, lane and sequencer blocks), layout 25 nets fewer than source, ports 64 vs 65, plus
   "ambiguity resolved arbitrarily" and "unbalanced smashed MOS" warnings. No texted short is reported (constant pad-
   control outputs that shared one net were the cause of the first run's short; each output port now has its own
   driver). Checked and ruled out: GDS / LEF pin geometry and labels of every used cell, M2 / via1 shapes outside the
   LEF, cell instance counts GDS vs netlist, layer datatypes. ICC2's own connectivity check is clean, so the suspects
   left are routing touching cell-internal metal that the LEF does not describe, or a deck setting. Not signed off.
2. **No pad ring / seal ring / fill.** Areas and power are for the core block; low-density DRC results are expected
   until fill.
3. **Headroom not taken** (by decision, no further redesign): letting placement merge clock gates cut the 250 MHz
   power from 10.6 to 5.5 mW (the clock-gate clock pins dominate) but needs an equivalence tool that accepts the
   cross-hierarchy merge (or the merge done in synthesis); a 2.6 ns DC netlist would raise Fmax towards ~380 MHz.
   The earlier merged layout is archived on the server (`build/summary_icgmerge/`).
4. SDF-annotated timing GLS of the routed netlist was not run (zero-delay GLS + STA only); IR drop / EM not analysed.
