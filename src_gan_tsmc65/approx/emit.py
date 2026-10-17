"""Verilog for a structured multiplier: one wire per gate of the netlist, the two final rows
x / y, and one `+` for the carry-propagate adder (synthesis picks its architecture)."""


def _ref(net, node, wire):
    op = net.ops[node]
    if op[0] == 'const':
        return f"1'b{op[1]}"
    if op[0] == 'in':
        return f'{op[1]}[{op[2]}]'
    return wire[node]


def _needed(net, roots):
    seen, stack = set(), list(roots)
    while stack:
        n = stack.pop()
        if n in seen:
            continue
        seen.add(n)
        if net.ops[n][0] in ('not', 'and', 'or', 'xor'):
            stack.extend(net.ops[n][1:])
    return sorted(seen)


def verilog(m, module, header, signed=True):
    net, w = m.net, 2 * m.n
    wire = {}
    body = []
    sym = {'and': '&', 'or': '|', 'xor': '^'}
    for node in _needed(net, list(m.x) + list(m.y)):
        op = net.ops[node]
        if op[0] in ('const', 'in'):
            continue
        wire[node] = net.names.get(node, f't{node}')
        if op[0] == 'not':
            expr = '~' + _ref(net, op[1], wire)
        else:
            expr = f' {sym[op[0]]} '.join(_ref(net, x, wire) for x in op[1:])
        body.append(f'    wire {wire[node]} = {expr};')
    s = 'signed ' if signed else ''
    rows = [', '.join(_ref(net, r[i], wire) for i in reversed(range(w))) for r in (m.x, m.y)]
    lines = ['`timescale 1ns / 1ps', ''] + [f'// {h}' if h else '//' for h in header] + [
        f'module {module} (',
        f'    input  wire {s}[{m.n - 1}:0]  a,',
        f'    input  wire {s}[{m.n - 1}:0]  b,',
        f'    output wire {s}[{w - 1}:0] p',
        ');'] + body + [
        f'    wire [{w - 1}:0] x = {{{rows[0]}}};',
        f'    wire [{w - 1}:0] y = {{{rows[1]}}};',
        '    assign p = x + y;',
        'endmodule', '']
    return '\n'.join(lines)
