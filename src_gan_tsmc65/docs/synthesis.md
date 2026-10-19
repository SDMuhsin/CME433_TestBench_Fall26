# gan65_chip on 65 nm: synthesis, equivalence, STA and gate-level check

Pre-layout results for `gan65_chip` (rtl/gan65.f) on the 65 nm standard-cell library,
using the exact multiplier unless a variant is named. Every number below is copied from a
summary file in `results/`. The full reports stay on the server under `build/`.

**Signoff point:** the DC netlist is synthesised at **1.8 ns** (ss) and signed off in
PrimeTime at **2.0 ns (500 MHz)**. This follows the src_int8_tsmc65 practice of synthesising
slightly tighter than the PT signoff clock, because PT with the DC SPEF is a few tens of ps
more pessimistic than DC.

## 1. Flow

| Step | Command (repo clone on the server) | Output |
|---|---|---|
| DC topographical, one run | `syn/scripts/run_dc.csh <period> [ss\|tt\|ff] [variant]` | `build/syn/<variant>_<corner>_p<period>/` |
| DC batch | `syn/scripts/run_batch.sh ss:2 ss:1.8 tt:1.8:exact ...` | one digest per run |
| Formality | `lec/run_fm.csh <syn_tag>` | `build/lec/<syn_tag>/` |
| PrimeTime | `sta/run_batch.sh <syn_tag>:<corner>[:max\|min[:period]] ...` | `build/sta/...` |
| Gate-level sim (VCS) | `sim/gls/run_gls.csh <syn_tag> [seed] [period] [saif]` | `build/gls/<syn_tag>_s<seed>/` |
| **Per-variant, one command** | `syn/run_syn.sh <variant> [--period 1.8] [--signoff [--sta-period 2.0]]` | DC + (FM + PT ss/tt/ff) |
| Fetch summaries | `sync.sh pull` (local) | `results/` |

- Variants resolve exactly as in the benchmark (`bench/variant.py`): `exact`, `<name>` for
  `bench/variants/<name>.v`, `mq:<name>` for an `mq_mul8` from src_int8, or a path.
- The flow reuses the 65 nm kit configuration and generic helpers of `src_int8_tsmc65`:
  - library and RC setup per corner (`syn/common/libs.tcl` and its git-ignored `site/`);
  - the area and timing summary procs (`summary.tcl`);
  - the constraints (`syn/constraints/mq65.sdc`);
  - the latch digest (`sta/latch_report.tcl`).
- Only the ICG wrapper is gan65-specific (`site/gan65_icg_site.v`, see `site/README.md`).

**Recipe** (`syn/scripts/dc_syn.tcl`):
- `compile_ultra -no_autoungroup -gate_clock`, then one incremental pass. There is no
  retiming.
- The minimum library is ff, with `set_fix_hold`.
- The PE, multiplier and memory hierarchies are kept.
- **`gan_mul8` keeps its boundary** (`set_boundary_optimization false`). This keeps its cell
  area the variant's own. With boundary optimisation on, DC moved input inverters across
  the ports, and the 16 exact multipliers came out at 7,810 instead of 7,984 um^2 (4 ns) and
  at 9,657 instead of 11,420 um^2 (1.8 ns).
- Compile uses a 30 ps larger hold uncertainty (see section 4). Reports and PT use the SDC's
  50 ps.

**Constraints** (mq65.sdc):
- clock uncertainty: 0.25 ns setup, 0.05 ns hold;
- clock transition: 0.15 ns;
- IO delays: 20 % of the period;
- max transition: min(0.5 ns, 0.1 x period);
- max fanout: 16.

The async host inputs (sclk, cs_n, io_in) are 2-FF synchronised. The IO delay is a
conservative stand-in for them.

## 2. Clock sweep (DC, ss, exact multiplier)

| DC period (ns) | Total area (um^2) | 16 x mul8 (um^2) | Setup WNS to flops (ns) | DC hold WNS (ns) | File |
|---|---|---|---|---|---|
| 4.0 | 168,847.9 | 7,984.1 | +0.0039 | +0.0009 | `results/syn_exact_ss_p4.txt` |
| 3.0 | 172,055.9 | 8,770.0 | +0.0042 | -0.0014 | `results/syn_exact_ss_p3.txt` |
| 2.5 | 174,414.6 | 9,939.2 | +0.0002 | +0.0017 | `results/syn_exact_ss_p2.5.txt` |
| 2.2 | 175,303.1 | 9,461.2 | +0.0001 | +0.0014 | `results/syn_exact_ss_p2.2.txt` |
| 2.0 | 178,960.7 | 10,285.6 | +0.0001 | -0.0066 | `results/syn_exact_ss_p2.txt` |
| **1.8** | **182,751.5** | **11,420.3** | **0.0000** | -0.0011 | `results/syn_exact_ss_p1.8.txt` |
| 1.6 | 193,793.0 | 17,823.6 | **-0.0120** | +0.0010 | `results/syn_exact_ss_p1.6.txt` |

- **DC Fmax (ss):** 1.8 ns is the shortest swept period that meets timing. 1.6 ns misses by
  12 ps, so DC closes at about 1.61 ns (about 620 MHz).
- From 2.5 ns down, the worst path through a multiplier (`setup_through_mul8`) is within
  0.1 ps of the overall worst path: A/B buffer read register (`u_rf/q_r`) -> `gan_mul8` ->
  PE accumulator (`acc_out`). The multiplier therefore sets Fmax, and a slower variant
  lowers it.
- At 3-4 ns the requant pipeline (`u_seq/u_rq`) is the worst path, with the multiplier path
  5-9 ps behind it.
- The latch RF write path borrows time: the 16,384 latch D endpoints sit at slack 0 by
  construction (see section 4).
- The table's "setup WNS" is the worst path into flops or outputs. The summaries also print
  the worst latch-inclusive slack, which reads 0.0000 because of that borrowing.

**PrimeTime Fmax** on the 1.8 ns netlist (ss, DC SPEF):

| PT period | Setup WNS to flops | File |
|---|---|---|
| 1.8 ns | -0.0170 ns (219 endpoints) | `results/sta_exact_ss_p1.8_ss_max.txt` |
| 1.9 ns | +0.0830 ns | `results/sta_exact_ss_p1.8_ss_max_at1.9.txt` |
| 2.0 ns | +0.1830 ns | `results/sta_exact_ss_p1.8_ss_max_at2.0.txt` |

The PT Fmax is therefore 1.817 ns (550 MHz). The signoff clock of 2.0 ns leaves 183 ps of ss
setup margin for layout.

## 3. Area of the signoff netlist (exact, ss, 1.8 ns)

Source: `results/syn_exact_ss_p1.8.txt`, sections `area_split`, `breakdown` and `hierarchy`.

| Block | Cells | Area (um^2) | Share |
|---|---|---|---|
| **Total** | 51,515 leaf cells | **182,751.5** (126,911 NAND2-eq) | 100 % |
| PE array (16 PEs) | 8,532 | 22,261.0 | 12.2 % |
| of which, the 16 multipliers alone | 4,059 | 11,420.3 (713.8 per mul8) | 6.2 % |
| of which, the rest of the PEs (accumulators, pipeline registers) | 4,473 | 10,840.7 | 5.9 % |
| **Memories: 8 x 256x8 latch RF** | 37,776 | **141,720.8** | **77.5 %** |
| of which, data latches | 16,384 | 82,575.4 | 45.2 % |
| of which, word ICGs | 2,056 | 13,322.9 | 7.3 % |
| of which, decode / read mux | 19,208 | 44,797.3 | 24.5 % |
| of which, wd_r / q_r flops | 128 | 1,025.3 | 0.6 % |
| Rest: host, CSR, sequencer + requant/tanh, controller, C buffer, glue | 5,207 | 18,769.7 | 10.3 % |

- **Rest, by block:**
  - sequencer `u_seq`: 8,881.2 um^2, which includes requant at 4,623.1 and the tanh ROM at
    1,109.9;
  - C buffer: 3,691.1;
  - CSR: 2,421.7;
  - host QSPI: 1,453.7;
  - DLA controller: 174.2.
- **DC power** (default activity, not a power number): 9.21 mW. Phase 3 gives real power
  (see the handoff).
- **Corner syntheses at 1.8 ns** (each corner's own library as target): tt 173,106.4 um^2
  (mul8 612.1 per instance), ff 168,040.8 um^2 (mul8 497.3). Files:
  `results/syn_exact_tt_p1.8.txt`, `results/syn_exact_ff_p1.8.txt`.

## 4. Formality and PrimeTime at the signoff clock

**Formality, RTL vs netlist** (`results/fm_exact_ss_p1.8.txt`):
- **SUCCEEDED**, with 20,170 passing compare points: 9 port, 1,729 DFF and 18,432 LAT. The
  LAT points are the 16,384 data latches plus the 2,048 latches inside the word ICGs.
- 0 failing, 0 aborted.
- 123 unmatched implementation LATCG: the clock gates that DC inserted, which have no RTL
  counterpart.
- SVF guidance: 228 accepted, 0 rejected.
- The tt and ff netlists and both variants below also pass: `results/fm_*.txt`.

**PrimeTime** on netlist ss_p1.8 at 2.0 ns (ideal clocks, DC SPEF; max RC for ss/tt, min RC
for ff):

| Corner | Setup WNS to flops | Hold WNS | Latch borrow (max) | RF read path slack | File |
|---|---|---|---|---|---|
| ss | **+0.183 ns** | +0.068 ns | 0.79 ns | +0.501 ns | `results/sta_exact_ss_p1.8_ss_max_at2.0.txt` |
| tt | +0.788 ns | +0.024 ns | 0.59 ns | +0.991 ns | `results/sta_exact_ss_p1.8_tt_max_at2.0.txt` |
| ff | +1.057 ns | **-0.0012 ns (2 endpoints, TNS -0.002 ns)** | 0.48 ns | +1.264 ns | `results/sta_exact_ss_p1.8_ff_min_at2.0.txt` |

**Open item, ff hold:**
- Two flop-to-flop paths miss hold by 1.2 ps at ff: `u_seq/u_rq/q_reg_*` to
  `u_seq/rq_res_reg_*`. Each is a direct Q to D connection across the requant hierarchy port.
- DC's hold fixing reduces the hold cost but stalls just short of zero on these paths. This
  happened with the default cost priority, with hold placed ahead of design rules, and with
  the 30 ps compile margin that the script now keeps.
- At other periods the residue is between -6.6 ps and +1.7 ps (table in section 2).
- Phase 3 also tried a hold-only pass; not supported in topographical mode (`docs/results.md` s.2).
- These are pre-layout numbers with ideal clocks. The hold fix after clock-tree synthesis in
  place and route takes care of them, as it does for any real skew.

**Other STA results:**
- Latch RF: the write data `wd_r` reaches the word latches inside the high phase, borrowing
  up to 0.79 ns at ss. No exception is needed (see mq65.sdc).
- The latch-input hold slack is above +1.0 ns at every corner.

## 5. Gate-level simulation (VCS, zero delay)

`sim/gls/run_gls.csh exact_ss_p1.8 0 2.0 1` runs the netlist (cell models, timing checks off)
under the unchanged benchmark TB at a 2.0 ns clock. The input is the latent
`model/fmnist/ref_vectors/seed_0/zq.memh`.

- **PASS:** all 784 pixels are bit-exact against `seed_0/expected.memh`, the golden integer
  model.
- The run takes 2,346,721 clk (the same as RTL) and 149 s of CPU time.
- Server log: `build/gls/exact_ss_p1.8_s0/tb.log`.

**Initial state:**
- Some datapath registers have no reset, and the RTL is only ever simulated in 2-state
  Verilator. The GLS therefore starts all state at 0 (`+vcs+initreg+0`).
- With all state X, every pixel is X: an X-pessimism artefact, not a design bug.
- With random initial state (`GAN65_GLS_INIT=random`, seed_1, 4 ns netlist) the result is
  also bit-exact.

**SAIF for power:** with `saif=1`, `sim/gls/gls_saif.sv` records `gan65_chip.saif` (9.6 MB).
- The window runs from the first START to the end of the STATUS check: 2,333,768 clk, which
  is the full stream load plus all three generator layers. Only the 784-byte pixel
  read-back (<1 %) falls outside it.
- Duration: 4.668 ms at 2.0 ns.

## 6. Multiplier variants (one command each)

`syn/run_syn.sh <variant> --signoff` gives DC at ss 1.8 ns, then Formality, then PT at
2.0 ns.

| Variant | Total area (um^2) | mul8 per instance (um^2) | 16 x mul8 | FM | PT ss setup @2.0 | PT ff hold | Files |
|---|---|---|---|---|---|---|---|
| exact | 182,751.5 | 713.8 | 11,420.3 | PASS | +0.183 | -0.0012 | `*exact_ss_p1.8*` |
| example_trunc4 | 179,186.8 | 646.4 | 10,342.1 | PASS | +0.189 | +0.0010 | `*example_trunc4_ss_p1.8*` |
| mq:ilm | 229,767.8 | 3,486.1 | 55,777.3 | PASS | **-0.345** (406 endpoints) | -0.0047 | `*mq_ilm_ss_p1.8*` |
| mq:evo_1KV8 | 194,649.8 | 1,299.9 | 20,799.0 | PASS | **-0.065** (183 endpoints) | +0.0008 | `*mq_evo_1KV8_ss_p1.8*` |
| mq:evo_1KR8 | 189,977.8 | 1,073.6 | 17,178.1 | PASS | **-0.005** (15 endpoints) | -0.0057 | `*mq_evo_1KR8_ss_p1.8*` |
| mq:evo_1KVL | 183,241.1 | 856.3 | 13,700.2 | PASS | +0.106 | +0.0007 | `*mq_evo_1KVL_ss_p1.8*` |
| mq:evo_1KR3 | 167,867.3 | 181.2 | 2,898.7 | PASS | +0.180 | -0.0005 | `*mq_evo_1KR3_ss_p1.8*` |

- `mq:ilm` is a log-domain multiplier with a much longer path. At this clock DC upsizes it
  heavily and it still fails ss setup at 2.0 ns.
- Each variant should be compared at a period it actually meets, e.g.
  `run_syn.sh mq:ilm --period 2.5 --signoff --sta-period 2.6`. Area always depends on the
  timing pressure, so a fair comparison uses one common clock that all candidates meet.
- The PT summaries also give the multiplier's own a/b -> p delay inside the chip
  (`mul8_a_to_p_delay`); minimum periods and these delays are in `docs/results.md` s.5.

## 7. The 16-bit datapath (`--width 16`, exact multiplier)

`syn/run_syn.sh exact --width 16 ...` runs the same flow on the INT16 chip (`docs/width16.md`);
tags carry `_w16`, and `build/syn/<tag>/width` tells Formality, GLS and power which model and
include directory to use.

| Netlist | Total area (um^2) | 16 x multiplier (um^2, per instance) | Latch RF (um^2) | DC setup | FM | PT ss setup / tt setup / ff hold | Files |
|---|---|---|---|---|---|---|---|
| `exact_w16_ss_p2.4` | 334,519.9 | 37,149.8 (11.1 %, 2,321.9) | 256,753.8 (76.8 %) | met | SUCCEEDED, 37,341 points, 0 failing | +0.083 / +0.927 / -0.0043 (6 endpoints) @2.5 | `*exact_w16_ss_p2.4*` |
| `exact_w16_ss_p1.8` | 374,886.7 | 64,423.4 (17.2 %, 4,026.5) | 261,314.6 (69.7 %) | -0.160 ns (568 endpoints) | not run | +0.025 @2.0 (ss) | `*exact_w16_ss_p1.8*` |

- Minimum period (method of s.2): 2.0 - 0.025 = **1.975 ns ss** (506 MHz), INT8 1.817 ns. The
  critical path is the INT8 one: A/B RF read register -> `gan_mul` -> 40-bit accumulator. The
  multiplier's own a -> p delay is 1.200 ns in the 1.8 ns netlist (INT8 0.937 ns) and 1.50 ns
  in the 2.4 ns one (sized for area).
- The ff hold endpoints of the 2.4 ns netlist are `u_seq/u_rq/q_reg_*` -> `u_seq/rq_res_reg_*`,
  the direct Q -> D pair of s.4, left to the P&R hold fix.
- Against the INT8 2.4 ns netlist (174,855.2 um^2) the chip is 1.91x: RF 1.86x (twice the
  bits, the same 2,048 word ICGs), multipliers 3.76x, PE array 2.89x.
- GLS: the zero-delay and the SDF-timed (tt) gate-level runs of seed_0 at 2.5 ns match the INT16 golden on
  784/784 pixels (4,606,025 clk); power is in `docs/width16.md` s.4.
