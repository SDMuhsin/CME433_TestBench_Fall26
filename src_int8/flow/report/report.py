#!/usr/bin/env python3
"""Signoff summary of one or more src_int8/flow runs (reads the LibreLane step state_out.json files).

    python3 src_int8/flow/report/report.py mq_final [other_tag ...]      # tags under src_int8/flow/runs/, or run dirs

Prints cells/area/util, routing, DRC/LVS/XOR/antenna, 9-corner setup/hold worst slack and
max slew/cap violation counts (signoff SDC), power, plus the KLayout DRC summary from kdrc.sh and the fill summary from fill/fill.sh.
"""
import glob
import json
import os
import sys

FLOW = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def metrics(run, pattern):
    g = sorted(glob.glob(os.path.join(run, pattern, 'state_out.json')))
    return json.load(open(g[-1]))['metrics'] if g else {}


def corners(m, key):
    pre = f'{key}__corner:'
    return {k[len(pre):]: v for k, v in m.items() if k.startswith(pre)}


def report(arg):
    run = arg if os.path.isdir(arg) else os.path.join(FLOW, 'runs', arg)
    c = metrics(run, '*-odb-cellfrequencytables')
    s = metrics(run, '*-misc-reportmanufacturability')
    p = metrics(run, '*-openroad-stapostpnr')
    a = metrics(run, '*-openroad-checkantennas-1')
    print(f'===== {os.path.basename(run)}')
    std = c.get('design__instance__count__stdcell', 0)
    fill = c.get('design__instance__count__class:fill_cell', 0)
    tap = c.get('design__instance__count__class:tap_cell', 0)
    print(f"  std cells {std} (excl. {fill} fill; incl. {tap} tap/endcap), "
          f"std-cell area {c.get('design__instance__area__stdcell', 0):,.0f} um^2, "
          f"macros {c.get('design__instance__count__macros')} ({c.get('design__instance__area__macros', 0):,.0f} um^2)")
    print(f"  util {100 * c.get('design__instance__utilization', 0):.1f}% (incl. macros), "
          f"std-cell util {100 * c.get('design__instance__utilization__stdcell', 0):.1f}%; "
          f"die {c.get('design__die__area', 0):,.0f} um^2 core {c.get('design__core__area', 0):,.0f} um^2")
    print(f"  seq {c.get('design__instance__count__class:sequential_cell')}, "
          f"repair buf {c.get('design__instance__count__class:timing_repair_buffer')}, "
          f"hold buf {c.get('design__instance__count__hold_buffer')}, "
          f"clk buf/inv {c.get('design__instance__count__class:clock_buffer')}/{c.get('design__instance__count__class:clock_inverter')}, "
          f"diodes {c.get('design__instance__count__class:antenna_cell')}")
    print(f"  route wirelength {c.get('route__wirelength', 0):,} um, route DRC {c.get('route__drc_errors')}, "
          f"OpenROAD antenna nets/pins {a.get('antenna__violating__nets', c.get('antenna__violating__nets'))}/"
          f"{a.get('antenna__violating__pins', c.get('antenna__violating__pins'))}")
    print(f"  Magic DRC {s.get('magic__drc_error__count')}, illegal overlap {s.get('magic__illegal_overlap__count')}, "
          f"LVS errors {s.get('design__lvs_error__count')}, XOR {s.get('design__xor_difference__count')}")
    kd = os.path.join(run, 'kdrc', 'summary.txt')
    print('  ' + (open(kd).read().strip() if os.path.exists(kd) else 'KLayout DRC: not run (src_int8/flow/drc/kdrc.sh)'))
    fs = os.path.join(run, 'fill', 'summary.txt')
    if os.path.exists(fs):
        print('  filled GDS (fill/fill.sh):')
        print('\n'.join('    ' + l for l in open(fs).read().strip().splitlines()[1:] if 'squares' not in l))
    if not p:
        print('  (no STAPostPNR)')
        return
    for typ in ('setup', 'hold'):
        cs = corners(p, f'timing__{typ}__ws')
        w = min(cs, key=cs.get)
        vio = sum(corners(p, f'timing__{typ}_vio__count').values())
        print(f'  {typ}: worst {cs[w]:+.3f} ns @ {w}, {vio} violations; ' +
              ' '.join(f'{k}={v:+.2f}' for k, v in sorted(cs.items())))
    for key in ('max_slew', 'max_cap', 'max_fanout'):
        cs = corners(p, f'design__{key}_violation__count')
        print(f'  {key} violations: total {sum(cs.values())}, worst corner {max(cs.values())}')
    # LibreLane's aggregated power__total is the LAST corner it reports (max_ss for this flow), not nom tt
    print(f"  power (vectorless, LibreLane power__total = max_ss corner; per-corner values in */power.rpt) {1e3 * p.get('power__total', 0):.1f} mW "
          f"(internal {1e3 * p.get('power__internal__total', 0):.1f}, switching {1e3 * p.get('power__switching__total', 0):.1f}, "
          f"leakage {1e6 * p.get('power__leakage__total', 0):.2f} uW)")


if __name__ == '__main__':
    for a in sys.argv[1:] or ['mq_final']:
        report(a)
