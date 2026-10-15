#!/usr/bin/env python3
"""Attribute cells of a flattened yosys/OpenROAD netlist to RTL hierarchy via net names.
Yosys keeps hierarchical wire names (\\u_core.u_x.y [3]); anonymous cells (_NNNN_) are attributed by
forward-tracing their output to the nearest hierarchically named net (fan-out cone, BFS), ties broken by
majority. Repair/CTS/antenna cells (fanout*/wire*/max_cap*/hold*/clk*/ANTENNA_*) are attributed via the
hierarchical name of the net they buffer (input side) and tagged by origin.
Usage: hier_attrib.py <netlist.v> <liberty.lib> <out.csv> [depth]  -> CSV inst,ref,area,origin,hier ; prints area by hier."""
import re, sys, os, collections
nl, lib, outcsv = sys.argv[1:4]; depth = int(sys.argv[4]) if len(sys.argv) > 4 else 3
rtl_files = sys.argv[5:]   # optional: RTL files; parent-level wires driven by a child's output port -> child instance
# --- RTL port map: (module, wire) -> child inst ------------------------------------------------
mod_outs = {}; mod_insts = {}   # module -> set(output ports); module -> [(child_mod, inst, {port: sig})]
for rf in rtl_files:
    src = re.sub(r'//.*', '', open(rf).read())
    for mm in re.finditer(r'\bmodule\s+(\w+)(.*?)\bendmodule', src, re.S):
        mod, body = mm.group(1), mm.group(2)
        mod_outs[mod] = set(re.findall(r'\boutput\s+(?:reg\s+|wire\s+|logic\s+)?(?:signed\s+)?(?:\[[^\]]*\]\s*)?(\w+)', body))
        insts = []
        for im in re.finditer(r'^\s*(\w+)\s+(?:#\s*\(.*?\)\s*)?(\w+)\s*\((.*?)\);', body, re.S | re.M):
            cm, inst, conns = im.groups()
            if cm in ('input', 'output', 'wire', 'reg', 'assign', 'always', 'if', 'else', 'for', 'logic', 'localparam', 'parameter', 'genvar', 'generate', 'begin', 'end', 'case', 'initial', 'integer'): continue
            insts.append((cm, inst, dict(re.findall(r'\.(\w+)\s*\(\s*(\w+)', conns))))
        mod_insts[mod] = insts
path_mod = {}  # hier path -> module
def walk(mod, path):
    for cm, inst, conns in mod_insts.get(mod, []):
        if cm in mod_insts or cm in mod_outs:
            path_mod[(path + '.' + inst) if path else inst] = cm; walk(cm, (path + '.' + inst) if path else inst)
tops = [m for m in mod_insts if not any(cm == m for il in mod_insts.values() for cm, _, _ in il)]
for t in tops: walk(t, '')
wire_child = {}  # (hierpath, wire) -> child inst
for path, mod in list(path_mod.items()) + [('', t) for t in tops]:
    for cm, inst, conns in mod_insts.get(mod, []):
        for port, sig in conns.items():
            if port in mod_outs.get(cm, ()): wire_child[(path, sig)] = inst
area = {}
cur = None
for line in open(lib):
    m = re.match(r'\s*cell\s*\(\s*"?([\w]+)"?\s*\)', line)
    if m: cur = m.group(1); continue
    m = re.match(r'\s*area\s*:\s*([\d.]+)', line)
    if m and cur: area[cur] = float(m.group(1)); cur = None
txt = open(nl).read()
# cells: ref inst ( .P(net), ... );  nets may be \name [idx] or _NNN_ or 1'bx
cell_re = re.compile(r'^\s*(gf180mcu_\w+)\s+(\\?\S+)\s*\((.*?)\);', re.S | re.M)
pin_re = re.compile(r'\.(\w+)\(\s*([^()]*?)\s*\)')
OUT = {'Q', 'Y', 'ZERO', 'ONE'}  # gf180mcu_as_sc output pins (S is the mux select INPUT)
def clean(n): return n.strip().lstrip('\\').replace(' ', '')
cells = []; drivers = {}; loads = collections.defaultdict(list)
for ref, inst, body in cell_re.findall(txt):
    inst = clean(inst); outs = []; ins = []
    for p, n in pin_re.findall(body):
        n = clean(n)
        if not n or n.startswith("1'"): continue
        (outs if p in OUT else ins).append(n)
    cells.append((inst, ref, outs, ins))
    for n in outs: drivers[n] = inst
    for n in ins: loads[n].append(inst)
def hier_of(net):
    n = re.sub(r'\[\d+\]$', '', net).lstrip('{\\')
    if '.' not in n: return None
    parts = n.split('.'); path, leaf = '.'.join(parts[:-1]), parts[-1]
    for _ in range(3):   # follow parent-level wires driven by a child's output down to that child
        c = wire_child.get((path, leaf))
        if not c: break
        path = path + '.' + c; leaf = None
    return '.'.join(path.split('.')[:depth])
def origin(inst, ref):
    for k in ('ANTENNA_', 'hold', 'fanout', 'wire', 'max_cap', 'max_length', 'clkbuf', 'clkload', 'TAP_', 'FILLER', 'input', 'output'):
        if inst.startswith(k): return {'ANTENNA_': 'diode', 'TAP_': 'tap', 'FILLER': 'fill', 'clkload': 'cts', 'clkbuf': 'cts',
                                       'input': 'iobuf', 'output': 'iobuf'}.get(k, k if k != 'max_length' else 'wire')
    if 'tie' in ref: return 'tie'
    if 'sram' in ref: return 'sram'
    return 'synth'
res = {}
def attrib(inst, outs, ins, orig):
    seeds = ins if orig not in ('synth', 'tie') else outs   # buffers: name of the buffered net (input side)
    seen = set(); frontier = list(seeds); d = 0
    while frontier and d < 12:
        hs = [hier_of(n) for n in frontier if hier_of(n)]
        if hs:
            if os.environ.get('HA_DEBUG') and inst in os.environ['HA_DEBUG'].split(','): print('DEBUG', inst, d, collections.Counter(hs).most_common(6), [n for n in frontier if hier_of(n)][:6], file=sys.stderr)
            return collections.Counter(hs).most_common(1)[0][0]
        nxt = []
        for n in frontier:
            for c in loads.get(n, []):
                if c in seen: continue
                seen.add(c)
                for cc in cmap.get(c, [[], []])[0]: nxt.append(cc)
        frontier = nxt; d += 1
    return '(unresolved)'
cmap = {i: (o, n) for i, _, o, n in cells}
tot = collections.defaultdict(lambda: [0, 0.0]); by_origin = collections.defaultdict(lambda: [0, 0.0])
with open(outcsv, 'w') as f:
    f.write('inst,ref,area,origin,hier\n')
    for inst, ref, outs, ins in cells:
        if 'fill' in ref: continue
        o = origin(inst, ref); h = 'top' if o in ('tap',) else attrib(inst, outs, ins, o)
        a = area.get(ref, 0.0)
        f.write(f'{inst},{ref},{a},{o},{h}\n')
        tot[h][0] += 1; tot[h][1] += a; by_origin[o][0] += 1; by_origin[o][1] += a
print(f'# {nl}'); print(f'{"origin":10s} {"cells":>7s} {"area_um2":>10s}')
for o, (c, a) in sorted(by_origin.items(), key=lambda x: -x[1][1]): print(f'{o:10s} {c:7d} {a:10.0f}')
print(f'{"hier":45s} {"cells":>7s} {"area_um2":>10s}')
for h, (c, a) in sorted(tot.items(), key=lambda x: -x[1][1])[:40]: print(f'{h[:45]:45s} {c:7d} {a:10.0f}')
