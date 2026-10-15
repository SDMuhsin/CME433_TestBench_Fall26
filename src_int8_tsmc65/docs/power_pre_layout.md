# mq_chip on 65 nm GP: pre-layout power from gate-level activity (phase 2)

Power of the DC netlist at the typical corner (tt 1.0 V 25 C), with switching activity
from a zero-delay gate-level simulation of a real workload. Everything is **pre-layout**:
no clock tree, ideal clocks, DC topographical RC estimates. The summaries are in
`results/pwr_*.txt`. Raw reports and SAIF stay on the server under
`~/CME433_TestBench_Fall26/src_int8_tsmc65/build/{gls,power}/`.

## 1. Method

1. **Activity**: `sim/gls/run_gls.csh tt_p4 tok2` runs the unchanged `src_int8` chip TB on
   the tt netlist (VCS, zero delay) at a **4 ns clock (250 MHz)**. The TB's 40 ns clock is
   rescaled with `-override_timescale=100ps/1ps`. `sim/gls/gls_saif.sv` is a second top
   level that records SAIF for the netlist instance over one TB `run_token()`: START, the
   54,280-byte weight/input stream, compute, STATUS and the 256-byte logit read-back. That
   is **455,312 clk = 1.821246 ms**, which matches the SAIF `DURATION`. The run also checks
   the outputs: 2/2 tokens bit-exact vs golden, and the state read-back is clean
   (`signoff_pre_layout.md` s.3).
2. **Window**: token 1 of the first story. It is a mid-story token with a non-zero
   recurrent state, so it is neither the zero-state token 0 nor a state reset. Every token
   runs the same fixed micro-code schedule (450,412 clk START -> done for all 31 tokens), so
   only the data changes the activity. Check: token 20 (second story, from the 31-token run
   `tt_p4_tok31_t20`) gives 7.386 mW against 7.393 mW for token 1 (-0.1 %). One token is
   therefore representative.
3. **Power**: `power/run_power.csh tt_p4 tt_p4_tok2` -> `power/pp_power.tcl` (PrimeTime PX
   Q-2019.12-SP2, averaged mode). It uses the netlist loader and SDC of the STA
   (`syn/common/pt_load.tcl`, 4 ns, tt library, typical-RC SPEF) plus `read_saif`.

**Annotation coverage: 100 %**. That is 58,544 / 58,544 nets and 55,382 / 55,382 leaf cells
from the SAIF. By class: 23,520 sequential, 32,125 combinational and 2,890 clock-gate cells,
all from the file. Nothing is default, propagated or implied.

## 2. Results at tt, 250 MHz

| | tt_p4, token 1 (main) | tt_p4, token 20 | ss_p3.9 sign-off netlist @ tt lib, token 1 |
|---|---|---|---|
| Cell internal | 6.314 mW | 6.311 mW | 6.301 mW |
| Net switching | 0.269 mW | 0.266 mW | 0.289 mW |
| Leakage | 0.810 mW | 0.809 mW | 0.829 mW |
| **Total (PrimeTime PX)** | **7.393 mW** | 7.386 mW | 7.419 mW |
| Annotation | 100 % | 100 % | 100 % |

Power groups (tt_p4, token 1): clock_network **6.190 mW (83.7 %)**, register 0.569 mW
(7.7 %), combinational 0.635 mW (8.6 %). By hierarchy: `u_core/u_mem` (the 11 latch RFs)
6.48 mW (HMEM 5.30, BMEM 1.18), datapath 0.44 mW (multiplier 0.14, writeback 0.22),
sequencer 0.21 mW, FIFO 0.10 mW, host 0.12 mW.

**The latch RF clock gates dominate.** Each of the 2,816 RF word ICGs, plus the 74 ICGs
that DC inserted, has its clock pin on the free-running clock. They burn about 6.1 mW of
internal power at 250 MHz (about 8 fJ per ICG per cycle), whether or not that word is
written. The latches, multiplier and the rest of the logic together use about 1.2 mW.
This is headroom, not a defect. A second level of clock gating would remove most of it: an
ICG per RF, or per group of words, enabled by `ce & we` in front of the word ICGs. That
change is left for a later revision.

**Not in the totals: the root clock net.** It is driven straight from the `clk` port (no
CTS), and PrimeTime PX assigns net switching power to the driving cell, so it reports 0 W
for this net. Its load is 5.19 pF of pin capacitance (2,967 pins, no wire RC on the ideal
clock) at 0.5 toggles/ns: 0.5 C V^2 f = **1.30 mW at 250 MHz** (1.0 V). After CTS the
clock tree buffers carry this power (and more).

## 3. Energy per token

The token time is 455,312 clk (START -> logit read-back). The dynamic energy per token
(internal + switching) is independent of the clock in a zero-delay, averaged analysis:
6.583 mW x 1.821246 ms = **11.99 uJ**. Leakage scales with the token time. Main run
(tt_p4, token 1):

| Clock | Token time | Average power | **Energy / token** | incl. root clock net (+2.36 uJ) |
|---|---|---|---|---|
| **250 MHz (4 ns sign-off clock)** | 1.821 ms | 7.39 mW | **13.5 uJ** | 15.8 uJ |
| 25 MHz (GF180 chip clock) | 18.21 ms | 1.47 mW | **26.7 uJ** (14.7 uJ of it leakage) | 29.1 uJ |

The 25 MHz row uses the same dynamic energy plus 0.810 mW x 18.21 ms of leakage. The ss
sign-off netlist gives 13.5 / 27.1 uJ (+0.4 % / +1.3 %).

For comparison, the GF180 mq_chip at 25 MHz uses 503 uJ / token (post-layout, SAIF), or
442 uJ with zero-delay GLS activity (`src_int8/docs/results.md` s.5). The 65 nm port at
the same 25 MHz is about 17-19x lower, and at 250 MHz it is 10x faster and 37x lower in
energy per token. Caveats: the 65 nm figures have no clock tree, no glitch power (zero-delay
activity; glitches were 12 % of the GF180 total) and no routed parasitics. Expect them to
rise after layout, mainly in the clock tree.

## 4. Artefacts

| What | Repo summary | Server (`build/`) |
|---|---|---|
| Main power run | `results/pwr_tt_p4_tt_p4_tok2.txt` | `power/tt_p4_tt_p4_tok2/` (`pp.log`, `rpt/{power,power_hier,switching,read_saif,not_annotated}.rpt`) |
| Token 20 check | `results/pwr_tt_p4_tt_p4_tok31_t20.txt` | `power/tt_p4_tt_p4_tok31_t20/` |
| Sign-off netlist @ tt | `results/pwr_ss_p3.9_ss_p3.9_tok31.txt` | `power/ss_p3.9_ss_p3.9_tok31/` |
| SAIF / GLS logs | - | `gls/tt_p4_tok2/`, `gls/tt_p4_tok31_t20/`, `gls/ss_p3.9_tok31/` (`tb.log`, `mq_chip.saif`) |
