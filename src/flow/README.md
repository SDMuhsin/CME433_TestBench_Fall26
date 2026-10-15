# mb_chip physical design flow (LibreLane 3.0.14, gf180mcuD)

This is the `dla_fp16_chip` recipe (`librelane/config_fp16.yaml`, run `fp16_final`) adapted to `mb_chip`. The die, pin template, PDN, antenna settings and slew/cap closure are the same. The SRAM count goes from 8 to 10, so there is a third macro row. Results are in `../docs/signoff.md`.

| Path | Purpose |
|---|---|
| `config.yaml` | LibreLane Classic config: RTL, macro placement (4+4+2 grid), floorplan, PDN, antenna and repair knobs |
| `build.sh <TAG>` | Full build in four steps: PnR → power-pin weld (`librelane/connect_power.py`) → streamout/DRC/LVS → SPEF + 9-corner STA |
| `env.sh` | `source` it for the nix LibreLane 3.0.14 shell, `PDK_ROOT` and the shims |
| `shims/` | `librelane` (adds `--pdk-root $PDK_ROOT --manual-pdk`) and `openroad-librelane` (→ `openroad`) |
| `sdc/base.sdc` | Common SDC body (LibreLane `base.sdc`); the limits come from the two wrappers |
| `sdc/pnr.sdc` | PnR SDC: 0.9 ns / 0.12 pF, over-constrained on purpose |
| `sdc/signoff.sdc` | Signoff SDC: 1.5 ns, liberty per-pin max_capacitance |
| `common/` | Shared helpers: `sta_corner.tcl` (Liberty/netlist/SDC/SPEF of one corner), `liberty.py` (reader), `libfunc.py` (Liberty functions, unateness), `netlist.py`, `names.py` |
| `drc/kdrc.sh <TAG>` | KLayout foundry DRC on the final GDS: main, antenna, density, plus the Vn.2b via-array check. LibreLane skips this check for gf180mcuD. `KDRC_GDS=... KDRC_OUT=...` runs it on another GDS (used for the filled GDS). |
| `drc/setup.sh` | Creates and checks the python env for `kdrc.sh` (`kdrc.sh` calls it). See "KLayout DRC environment" below. |
| `drc/{build-,}requirements.txt` | Hash-pinned pip inputs: setuptools 80.9.0 (build backend only), docopt 0.6.2 |
| `drc/deck.sha256` | sha256 of the PDK's `run_drc.py` and all 68 `rule_decks/*.drc` (open_pdks 7b70722e) |
| `fill/fill.sh <TAG>` | Runner: Metal1-5 dummy fill of `final/gds/mb_chip.gds` -> `final/gds_filled/mb_chip.gds`, plus all fill checks (see "Metal fill" below) |
| `fill/fill_sta.sh <TAG>` | Runner: RCX + 9-corner STA with the fill as a grounded net -> run `<TAG>_fillrc` |
| `fill/fill_signoff.sh <TAG>` | Runner: LibreLane Magic DRC + Magic GDS extraction + Netgen LVS on the filled GDS -> run `<TAG>_fillsignoff` |
| `fill/gen/fill.py` | The fill generator (GF180MCU DRM 13.3 rules, PDK fill pattern) |
| `fill/checks/check_fill.py` | XOR vs the unfilled GDS, fill isolation (floating), DM.1/2b/3/4-7/8 coded against drawn metal |
| `fill/checks/density.py` | Whole-area coverage per layer (the `density.drc` rules) and the 200 um / 100 um window coverage |
| `fill/checks/die_model.py` | Worst-case die: A56/ACV padring IO cells + this block, the rest of the die left empty |
| `fill/checks/dummy_drc.sh`, `fill/checks/lyrdb_count.py` | The PDK dummy-metal decks DM1-DM5 (which `run_drc.py` never enables); `.lyrdb` item counts |
| `fill/rc/` | Fill parasitics for `fill_sta.sh`: `export_fill.py` (squares -> text), `fill_odb.py` (grounded special net in the ODB), `spef_delta.py` (per-net ΔC between two runs) |
| `gls/run_gls.sh [nl\|pnl]` | Zero-delay gate-level sim of `final/{nl,pnl}` with the chip TB (`src/tb/chip`), checked bit-exact against `src/golden` |
| `sdf_gls/run_sdf_gls.sh <corner>` | Timing-annotated GLS: SDF from the signoff STA, active timing checks, SDC pad timing, Open Source CVC (see "Timing-annotated GLS" below) |
| `power/run_power.sh [corners]` | Activity-based power: SDF-GLS VCD of one token -> per-pin SAIF -> OpenSTA `report_power` (see "Activity-based power" below) |
| `report/report.py <TAG>` | Signoff metrics summary read from the run's step states |
| `report/render.tcl` | Layout PNG (OpenROAD `save_image`) |
| `logs/` | Build / GLS logs of the final runs (git-ignored `*.log`) |
| `runs/`, `build/` | LibreLane runs and simulation / power build products (git-ignored) |

Shared, read-only inputs (not copied):
- `librelane/A56_ACV.def` (pin template)
- `librelane/pdn_cfg.tcl` (SRAM M3→M4 PDN connect)
- `librelane/connect_power.py`
- `gf180mcu_ocd_ip_sram__sram256x8m8wm1/` (macro views)

## Commands (from the repo root, after `source src/flow/env.sh`)

```
src/flow/build.sh mb_final                 # ~15 min, runs land in src/flow/runs/<TAG> (git-ignored)
src/flow/drc/kdrc.sh mb_final              # ~8 min; creates src/flow/drc/.venv on first use
src/flow/fill/fill.sh mb_final             # ~20 min: fill + checks + KLayout DRC of the filled GDS
src/flow/fill/fill_sta.sh mb_final         # ~1 min: RCX/STA with fill -> runs/mb_final_fillrc
src/flow/fill/fill_signoff.sh mb_final     # ~3 min: Magic DRC + GDS-extracted LVS -> runs/mb_final_fillsignoff
python3 src/flow/report/report.py mb_final
src/flow/gls/run_gls.sh nl  &  src/flow/gls/run_gls.sh pnl    # 31 tokens, ~2 h each (Icarus)
src/flow/gls/run_gls.sh nl -- --story "Once"   # other vectors (args go to python -m src.golden.host.vectors)
QT_QPA_PLATFORM=offscreen openroad -no_init -exit src/flow/report/render.tcl
VEC=src/flow/build/sdf_gls/vec_31 src/flow/sdf_gls/run_sdf_gls.sh max_ss_125C_3v00   # 31 tokens, ~3 h per corner
src/flow/power/run_power.sh                 # ~35 min: 3 corners + zero-delay, -> build/power/summary.rpt
```

LibreLane must be called with `--pdk-root /root/.ciel-chipathon --manual-pdk`. The `shims/librelane` wrapper adds both. The PDK is open_pdks 7b70722e with the AS 3V3 library merged in.

`env.sh` needs three things on the machine that are not in the repo:
- nix;
- the LibreLane 3.0.14 devshell, gc-rooted at `/opt/librelane/devshell-3.0.14` and dumped to `/opt/librelane/devshell-3.0.14.sh`;
- the PDK at `/root/.ciel-chipathon`.

To use other locations, set `LIBRELANE_DEVSHELL` or `PDK_ROOT` before sourcing.

## KLayout DRC environment

The PDK deck driver (`$PDK_ROOT/gf180mcuD/libs.tech/klayout/tech/drc/run_drc.py`) needs two python modules:
- `klayout.db`, which the nix devshell `python3` provides;
- `docopt`, which nothing in nix provides.

It also calls the `klayout` binary (`klayout -b -r`). `drc/setup.sh` does the following:
1. Checks `klayout -b -v` = 0.30.7, `PDK_ROOT/gf180mcuD/SOURCES` = open_pdks 7b70722e, and the deck files against `deck.sha256`.
2. Creates `src/flow/drc/.venv` (git-ignored) with `python3 -m venv --system-site-packages`, so `klayout.db` comes from nix.
3. Installs setuptools, then docopt with `--require-hashes --no-build-isolation`. No unpinned package is downloaded. This step needs PyPI access once.
4. Checks that the venv imports `klayout.db` 0.30.7 and docopt 0.6.2.
5. Prints the venv python.

Use `FRESH=1 src/flow/drc/setup.sh` to rebuild the venv. To use another python, set `KPY=...` for `drc/kdrc.sh`; this skips `setup.sh`.

## Metal fill

`mb_chip` is a block for the A56 die, in the ACV slot: 1675 x 1110 um at (350, 1475) inside the
2935 x 2935 um GF180 padring (`layout_announcement/A56.def/A56/project_defs/ACV/`). It is not a
full chip. The deliverable is the filled GDS `runs/<TAG>/final/gds_filled/mb_chip.gds`; the unfilled
`final/gds/mb_chip.gds` stays as LibreLane wrote it.

**Rules** (GF180MCU DRM 13.3, <https://gf180mcu-pdk.readthedocs.io/en/latest/physical_verification/design_manual/drm_13_3.html>):
- DM.1: dummy squares are exactly 2.0 x 2.0 um.
- DM.2a: 1.2 um space between dummy squares (DM.2b, the coded check, is 0.98 um).
- DM.3: 2.0 um to circuit metal on the same layer.
- DM.4-DM.7: 1.0 um to the metal layers above and below, and no overlap with them.
- DM.8: 6 um to fuse, PMNDMY, MTP and OTP markers.
- Density target: the DRM recommends 30 % minimum metal coverage. `density.drc` codes this per layer over the whole GDS bbox (M1.4 ... M5.4, plus MT.3, which is Metal5 again for 5LM). The tech LEF adds a 200 x 200 um window with a 100 um step. Neither source gives a maximum density.

**`gen/fill.py`** follows the PDK `filler_generation/fill_metal.rb` pattern:
- squares on a lattice of (3.2, 0.5) / (0.5, 3.2) um, with a 0.5 um origin shift per layer (DM.9/DM.10);
- four passes, each shifted by half a pitch, to reach the slivers the first lattice misses.

It differs from the PDK script in four ways:
- DM.4-DM.7 are applied at the DRM value of 1 um. The PDK script uses 2 um, or nothing at all.
- There is no 26 um scribe ring. A 2 um edge band is kept instead, so DM.3 holds against whatever the integrator places outside the block.
- Metal1-3 are not filled inside the SRAM macro bboxes, which the LEF OBS reserves.
- The fill cells are named `mb_chip_*`, so they cannot clash when the shuttle GDS is merged.

KLayout's `Cell.fill_region` with skewed steps writes duplicate instances. `gen/fill.py` therefore places the squares from its own lattice.

**Checks run by `fill.sh`.** Results go to `runs/<TAG>/fill/summary.txt` and `runs/<TAG>/kdrc_filled/`.
- `checks/check_fill.py`:
  - flat XOR of every non-dummy layer = 0, and no original cell changed;
  - every dummy shape is a 2 x 2 um square;
  - no dummy square touches circuit metal, a via or contact, a label or the edge band;
  - DM.2b/3/4-7/8 measured against drawn metal.
- `checks/dummy_drc.sh`: the PDK DM1-DM5 decks. Their DMn.3 check is shielded by the dummy's own copy in `metalN = drawn + dummy`, so it misses a dummy square 1 um from drawn metal and catches only overlaps. This was shown on a 2-shape test layout, and it is why `checks/check_fill.py` is the DM.3 authority.
- `drc/kdrc.sh` on the filled GDS.
- the foundry `density.drc` on the `checks/die_model.py` worst-case die.

**Parasitics.** `fill_sta.sh` adds the squares to `_connected.odb` as a GROUNDED special net (`FILL_GND`). It then reruns LibreLane `OpenROAD.RCX` + `OpenROAD.STAPostPNR` with the same config. Grounded fill gives an upper bound, because the real fill floats. Results are in `../docs/signoff.md`.

## Timing-annotated GLS (`sdf_gls/`)

`run_sdf_gls.sh <corner>` simulates the routed netlist with the corner's SDF and every timing
check active; it prints `RESULT ... PASS` only for bit-exact logits, 0 timing-check violations,
0 SRAM-model errors, 0 output-timing violations and 100 % SDF annotation. Results:
`../docs/signoff.md` ("Timing-annotated GLS").

| Sub-dir / file | Purpose |
|---|---|
| `run_sdf_gls.sh` | Runner; env `RUN KIND VEC NTOK MAXCYC PROGRESS VCD_TOK TCLK SKEW PROBE NOSDF TAG` (header) |
| `tools/setup_cvc.sh`, `tools/cvc_sdf.patch` | Builds Open Source CVC 7.00b (pinned commit) in `tools/.cvc` (git-ignored) with two SDF-reader fixes. Icarus cannot be used: it ignores `$setuphold` & co. |
| `models/gen_cells.py` | Std-cell models with specify blocks generated from the Liberty arcs (paths, `$setuphold` per data edge, `$width`, `$recrem`, notifier -> X) around the library's functional bodies |
| `models/sram_sdf.v` | SRAM macro model: the vendor model with 3.3 V Liberty specparams, unconditional CEN checks, CVC fixes (notes 1-6 in the header) |
| `models/sram_zd.v` | Zero-delay SRAM model for the `NOSDF=1` reference run |
| `sdf/write_sdf.tcl` | Signoff STA of one corner (via `common/sta_corner.tcl`), slack reports, arc order, `write_sdf` (identical to LibreLane's) |
| `sdf/fix_sdf.py` | COND on the paired non-unate IOPATHs (xor/xnor/mux2), legal names for the escaped SRAM instances |
| `sdf/legal_netlist.py` | Netlist copy with the same instance renaming |
| `sdf/skew_sdf.py` | Negative tests: extra delay on the INTERCONNECTs into given pins |
| `checks/sdf_coverage.py` | Annotation coverage from the CVC `+sdfverbose` log (statements, instances, model checks) |
| `checks/margin_probe.py` | Margin probe: inflate all SETUP or HOLD limits by P, collect the observed margins |
| `checks/model_selftest/` | `run.sh` + `tb_selftest.v` + `selftest.sdf`: 10 s test of the CVC behaviours the models rely on (CLK->Q through an INTERCONNECT, SRAM read through bit INTERCONNECTs, edge-specific setup, negative hold); run first by `run_sdf_gls.sh` |
| `checks/summarize.py` | Table of all runs in `build/sdf_gls` -> `build/sdf_gls/summary.rpt` |

The TB is `src/tb/sdf/` (Verilog-2001 port of the chip TB with SDC pad timing, `io_mon.vh`
output-delay monitor, `sram_mon.vh` access counters). Build dirs: `build/sdf_gls/<corner>[_TAG]`
(`gls.log`, `coverage.rpt`, `timing.rpt`, `margin.rpt`), SDFs/STA reports in `build/sdf_gls/sdf/`.

```
src/flow/sdf_gls/run_sdf_gls.sh min_ff_n40C_3v60                       # default 31-token set
VEC=<dir> NTOK=1 PROBE="hold 1.0"   TAG=probe_hold  src/flow/sdf_gls/run_sdf_gls.sh min_ff_n40C_3v60
VEC=<dir> NTOK=1 PROBE="setup 26.0" TAG=probe_setup src/flow/sdf_gls/run_sdf_gls.sh max_ss_125C_3v00
VEC=<dir> NTOK=1 SKEW="u_core_u_mem_GEN_SRAM_0__u_sram_u_sram.CLK=2.0" TAG=neg_hold_sram0 \
    src/flow/sdf_gls/run_sdf_gls.sh min_ff_n40C_3v60                   # must FAIL
```

## Activity-based power (`power/`)

| Sub-dir / file | Purpose |
|---|---|
| `run_power.sh` | Runner: SDF GLS with VCD per corner (+ zero-delay reference), SAIF, `report_power`, summary |
| `activity/vcd2saif.py` | Net VCD of the flat netlist -> SAIF with an entry per instance pin (OpenSTA annotates pins, not internal nets) |
| `report/power.tcl` | OpenSTA power of one corner: SAIF or vectorless, optional flop proxy; groups, SRAM and flop reports, annotation |
| `report/proxy_lib.py` | Proxy Liberty for the flops (the AS Liberty has no flop internal power and no leakage) |
| `report/power_summary.py` | `build/power/summary.rpt`: tables, SRAM access-count check, energy/token |
