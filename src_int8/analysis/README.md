# analysis/ -- area and power investigation of mq_chip vs mb_chip

Read-only on `flow/runs/*` and `src/flow/runs/*`; outputs go to `analysis/data/` (kept) and `analysis/build/`
(git-ignored). Report: `area_power.md`. Scripts take their inputs as arguments and run from the repo root.

| Dir / file | purpose |
|---|---|
| `area/cmp_metrics.py [regex]` | diff `final/metrics.json` of mq_final vs mb_final |
| `area/cell_growth.py` | per-step cell count by class (logic/buf/ff/tap/diode/tie) from each step's `*.nl.v`, both runs -> `data/cell_growth.txt` |
| `area/hier_attrib.py <nl.v> <lib> <out.csv> [depth] [rtl files]` | attribute flattened cells to RTL hierarchy (forward trace to named nets; parent-level wires resolved through the RTL port map); area by hierarchy and by origin (synth/cts/fanout/wire/max_cap/hold/diode/tap) -> `data/{mq,mb}_{synth,final}.txt` |
| `area/repair_nets.py <final.nl.v> <attrib.csv> <power_inst.rpt>` | which source nets the fanout/wire/max_cap/hold buffers and antenna diodes sit on, with their power -> `data/repair_*.txt` |
| `power/run_power_instances.sh`, `power/power_instances.tcl` | OpenSTA `report_power -instances` for all cells using the flow's `sta_corner.tcl`, signoff SDC, SPEF and the existing SAIF (nom_tt; SDF and zero-delay) -> `build/power/power_inst.*.rpt` |
| `power/power_by_hier.py <power_inst.rpt> <attrib.csv>` | power by hierarchy / origin / cell type, per-hierarchy clock-vs-logic-vs-repair split -> `data/pow_*.txt` |
| `power/saif_toggles.py <nl.v> <attrib.csv> <cycles> <saif> [<saif_zd>] -- bus...` | toggles/bit/cycle and duty of named buses, mean output toggles per hierarchy, SDF/zero-delay glitch ratio -> `data/tog_*.txt` |
| `data/config_diff.txt` | `diff flow/config.yaml src/flow/config.yaml` |

Reproduce: `src_int8/analysis/power/run_power_instances.sh` (sources `flow/env.sh`, writes `analysis/build/power/`), then the
Python scripts with `/root/.ciel-chipathon/gf180mcuD/libs.ref/gf180mcu_as_sc_mcu7t3v3/lib/gf180mcu_as_sc_mcu7t3v3__tt_025C_3v30.lib`.
