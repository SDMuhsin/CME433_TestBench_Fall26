# mq_chip -> 65 nm: feasibility summary

Public summary of a survey of the tools and process kit available for porting `mq_chip` to a
commercial 65 nm GP process accessed through CMC Microsystems. Kit names, paths, versions and
server details are deliberately left out (they are covered by the kit's license terms); the
flow scripts in `src_int8_tsmc65/` read them from a git-ignored site config
(`src_int8_tsmc65/site/README.md`).

## Verdict

**Feasible with a Synopsys + Siemens Calibre flow, the foundry's own standard cells and a
standard-cell (latch-based) memory.** Every step runs from batch scripts:
Synopsys DC synthesis -> ICC2 place and route -> StarRC / PrimeTime STA -> Calibre
DRC / LVS / antenna / fill -> VCS SDF gate-level simulation -> PrimePower. Formality covers
logic equivalence. A Cadence flow was not available to this account at survey time.

## Findings

- **Standard cells.** One RVT standard-cell library has full front-end and back-end views
  (timing/power .db at several PVT corners, Verilog, LEF, GDS, CDL, techfiles and RC tech
  files). It is the library used by the flow.
- **Memories.** No SRAM with back-end (GDS / LVS) views is available, so the 11 `256 x 8`
  SRAM macros of the GF180 chip are replaced by a 256 x 8 latch register file
  (`src_int8_tsmc65/rtl_mem/`) behind the same wrapper, keeping the 1-cycle read.
  Estimated size 0.15-0.25 mm^2 for the 22.5 kbit.
- **IO and pads.** 2.5 V GPIO, wire-bond pad and seal-ring views are provided, so the chip
  can be a pad-ring design in a 1P9M stack.
- **Signoff.** Calibre DRC / LVS / antenna / fill decks are present. Parasitic extraction
  for the typical corner is available from StarRC; worst / best corners come from the
  place-and-route RC models.
- **Shuttle.** MPW block sizes, pad-frame and GDS-merge rules must be requested from CMC.

## Plan, effort and risks

| Need | Plan |
|---|---|
| 11 x 256x8 SRAM | Latch register file with one clock gate per word (done, `rtl_mem/`) |
| Synthesis / LEC | Batch DC and Formality scripts (`syn/`, `lec/`) |
| PnR | ICC2 from LEF + .db + techfile + RC tech files |
| STA / power | PrimeTime at ss / ff, PrimePower with SAIF from GLS |
| Physical verification | Calibre DRC / LVS in batch |
| GLS | Reuse the `src_int8` test benches with the SDF netlist |

- **Effort.** About 3-5 person-weeks, mostly new Synopsys flow scripts (no reference flow is
  provided with the kit): DC / ICC2 / PT 1.5-2 weeks, memory replacement and re-verification
  about 1 week, pad ring and DRC / LVS cleanup 1-1.5 weeks, GLS and power a few days.
- **Risks.** Older tool releases and signoff decks, typical-corner-only extraction, pad CDL
  availability for clean LVS, and unknown shuttle rules.
- **Timing.** The GF180 chip's 40 ns clock is trivial at 65 nm; 5-10 ns looks achievable.
