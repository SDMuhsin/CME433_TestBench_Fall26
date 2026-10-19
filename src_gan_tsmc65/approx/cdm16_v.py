"""Verilog of the 16 x 16 carry-disregard multiplier CDM16_wxyz (Amirafshar et al., IEEE TCAS-I
2023, Fig. 5, Table II), bit-exact with cdm.unsigned16 / cdm.signed16.

Four CDM8 sub-multipliers (bit-level netlists of cdm.cdm(x, y, 'unsigned'), one module per
distinct CDM8) on A_L B_L, A_H B_L, A_L B_H, A_H B_H, and the four 8-bit adders CLAx1-4 that
drop their carry out: two 3-operand 8-bit sums (written as one `+` each, mod 2^8). Signed
(sign-magnitude, the scheme of the 8-bit cdm_* variants): 15-bit one's-complement magnitudes
into the unsigned CDM16, the exact correction terms a15 |b|' + b15 |a|' + a15 b15, and the
product sign applied by an exact negation.
"""
from .cdm import CDM16_DIGIT, cdm
from .emit import verilog as netlist_verilog

SUBS = ('al', 'bl'), ('ah', 'bl'), ('al', 'bh'), ('ah', 'bh')


def _sub_name(pre, xy):
    return f'{pre}_cdm8_{xy[0]:x}{xy[1]:x}'


def verilog(digits, header, module='mul_core', signed=False):
    pre = f'cdm16_{digits}'
    xys = [CDM16_DIGIT[d] for d in digits]
    lines = ['`timescale 1ns / 1ps', ''] + [f'// {h}' if h else '//' for h in header]
    for xy in sorted(set(xys)):
        sub = netlist_verilog(cdm(*xy, mode='unsigned'), _sub_name(pre, xy),
                              [f'unsigned 8 x 8 CDM8_{xy[0]:x}{xy[1]:x} (cd_{xy[0]:x} on A x B_L, '
                               f'cd_{xy[1]:x} on A x B_H; cd_1 = exact)'], signed=False)
        lines += [''] + sub.split('\n')[2:-1]
    core = f'{pre}_u' if signed else module
    lines += ['', f'// unsigned CDM16_{digits}: MUL_1..MUL_4, CLAx1-2 and CLAx3-4 without carry out',
              f'module {core} (',
              '    input  wire [15:0] a,',
              '    input  wire [15:0] b,',
              '    output wire [31:0] p',
              ');',
              '    wire [7:0] al = a[7:0], ah = a[15:8], bl = b[7:0], bh = b[15:8];']
    for i, (xy, (x, y)) in enumerate(zip(xys, SUBS), 1):
        lines += [f'    wire [15:0] r{i};',
                  f'    {_sub_name(pre, xy)} u_m{i} (.a({x}), .b({y}), .p(r{i}));']
    lines += ['    wire [7:0] s1 = r1[15:8] + r2[7:0] + r3[7:0];     // CLAx1-2, carry out dropped',
              '    wire [7:0] s2 = r2[15:8] + r3[15:8] + r4[7:0];    // CLAx3-4, carry out dropped',
              '    assign p = {r4[15:8], s2, s1, r1[7:0]};',
              'endmodule']
    if signed:
        lines += ['', f'// signed CDM16_{digits}, sign-magnitude',
                  f'module {module} (',
                  '    input  wire signed [15:0] a,',
                  '    input  wire signed [15:0] b,',
                  '    output wire signed [31:0] p',
                  ');',
                  '    wire sa = a[15], sb = b[15];',
                  "    wire [15:0] am = {1'b0, a[14:0] ^ {15{sa}}};    // |a| = am + sa",
                  "    wire [15:0] bm = {1'b0, b[14:0] ^ {15{sb}}};",
                  '    wire [31:0] u;',
                  f'    {core} u_core (.a(am), .b(bm), .p(u));',
                  "    wire [31:0] v = u + (sa ? {16'd0, bm} : 32'd0) + (sb ? {16'd0, am} : 32'd0) + (sa & sb);",
                  '    assign p = (sa ^ sb) ? -$signed(v) : $signed(v);',
                  'endmodule']
    return '\n'.join(lines + [''])
