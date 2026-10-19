"""Verilog of a signed 8 x 8 HAM gan_mul8 (Shi et al., IEEE TVLSI 2025, 8-bit H7C0 HAM-A/B/C),
bit-exact with ham.signed for an 8-bit HnC0 configuration. Behavioural datapath as in the
paper (Fig. 3): magnitude extraction (PACC or exact), leading-one detector + exponent /
mantissa conversion, mixed PWL (X1..X4, zone select, three-term adder with the zone bias),
sign compensation (bias - 1 plus the vacant carry bit ~sign, then one's complement), shift
by K, zero flag.
"""


def _me(x, me):
    if me == 'pacc':
        return [f"    // ME, partial complement: ~{x}[6:4] and ~{x}[3:0] + 1 without carry out",
                f'    wire [6:0] i{x} = ~{x}[6:0];',
                f"    wire [3:0] l{x} = i{x}[3:0] + 4'd1;",
                f'    wire [6:0] m{x} = {x}[7] ? {{i{x}[6:4], l{x}}} : {x}[6:0];']
    return [f"    // ME, exact two's-complement magnitude (|-128| = 128 needs 8 bits)",
            f'    wire [7:0] m{x} = {x}[7] ? -{x} : {x};']


def verilog(h, name, header, module='gan_mul8'):
    """h: ham.Ham with w = 8, m = 0, c = 0 (q = F = n - 2)."""
    assert h.w == 8 and h.m == 0 and h.c == 0 and h.bf == h.F and h.signed and h.mts == 'sc'
    mw = 8 if h.me == 'exact' else 7               # magnitude bits
    kw = 3                                         # leading-one position 0..mw-1
    F = h.F                                        # mantissa / p1 fraction bits
    pw = F + 2                                     # p1_PWL bits
    z1, z5, z2, z4 = h.zones
    b = [v - 1 for v in h.biases]                  # sign compensation: biases pre-reduced by 1
    x2, x3 = h.x2b, h.x3b
    x4mask = ((1 << h.x4b) - 1) << (F - h.x4b)
    lines = ['`timescale 1ns / 1ps', ''] + [f'// {t}' if t else '//' for t in header] + [
        '',
        f'// exponent / mantissa conversion: x (> 0) -> k = leading-one position, f = the {F}',
        '// bits after the leading one',
        f'module {name}_emc (',
        f'    input  wire [{mw - 1}:0] x,',
        f'    output reg  [{kw - 1}:0] k,',
        f'    output wire [{F - 1}:0] f',
        ');',
        '    integer i;',
        '    always @* begin',
        '        k = 0;',
        f'        for (i = 1; i < {mw}; i = i + 1)',
        '            if (x[i]) k = i;',
        '    end',
        f'    wire [{mw - 1}:0] xs = x << ({mw - 1} - k);       // leading one to bit {mw - 1}',
        f'    assign f = xs[{mw - 2}:{mw - 1 - F}];',
        'endmodule',
        '',
        f'// mixed PWL fit of (1 + f1)(1 + f2) in units of 2^-{F}, sign compensated: the result is',
        f'// p1 for neg = 0 and p1 - 1 for neg = 1',
        f'module {name}_pwl (',
        f'    input  wire [{F - 1}:0] f1,',
        f'    input  wire [{F - 1}:0] f2,',
        '    input  wire       neg,',
        f'    output wire [{pw - 1}:0] s',
        ');',
        f'    wire [{F}:0] x1 = f1 + f2;',
        f'    wire signed [{x2}:0] x2 = $signed({{1\'b0, f1[{F - 1}:{F - x2}]}}) - $signed({{1\'b0, f2[{F - 1}:{F - x2}]}});',
        f'    wire [{x2 - 1}:0] ax2 = x2[{x2}] ? -x2[{x2 - 1}:0] : x2[{x2 - 1}:0];',
        f'    wire [{x3}:0] x3 = f1[{F - 1}:{F - x3}] + f2[{F - 1}:{F - x3}];',
        f"    wire [{F - 1}:0] x4 = (x2[{x2}] ? f1 : f2) & {F}'b{x4mask:0{F}b};   // min(f1, f2), {h.x4b} MSBs",
        f'    wire zn1 = x3 < {z1};',
        f'    wire zn5 = x3 >= {z5};',
        f'    wire zn2 = ~zn1 & ~zn5 & (ax2 <= {z2});',
        f'    wire zn4 = ~zn1 & ~zn5 & (ax2 >= {z4});',
        f'    wire [{pw - 1}:0] t1 = zn5 ? {{x1, 1\'b0}} : {{1\'b0, x1}};',
        f'    wire [{pw - 1}:0] t2 = zn1 ? x4 >> 2 : zn4 ? x4 : zn5 ? -(x1 >> 4) : x1 >> 1;',
        f"    wire [{pw - 1}:0] bias = zn1 ? {pw}'d{b[0]} : zn5 ? {pw}'d{b[4]} : zn2 ? {pw}'d{b[1]} :",
        f"                        zn4 ? {pw}'d{b[3]} : {pw}'d{b[2]};",
        f'    assign s = t1 + t2 + bias + {{{pw - 1}\'d0, ~neg}};   // vacant carry bit = ~sign',
        'endmodule',
        '',
        f'module {module} (',
        '    input  wire signed [7:0]  a,',
        '    input  wire signed [7:0]  b,',
        '    output wire signed [15:0] p',
        ');'] + _me('a', h.me) + _me('b', h.me) + [
        f'    wire [{kw - 1}:0] ka, kb;',
        f'    wire [{F - 1}:0] fa, fb;',
        f'    {name}_emc u_ea (.x(ma), .k(ka), .f(fa));',
        f'    {name}_emc u_eb (.x(mb), .k(kb), .f(fb));',
        '    wire neg = a[7] ^ b[7];',
        f'    wire [{pw - 1}:0] s;',
        f'    {name}_pwl u_pwl (.f1(fa), .f2(fb), .neg(neg), .s(s));',
        '    // MTS: one\'s complement of the compensated result (= -p1 for a negative product)',
        f'    wire signed [{pw}:0] o = {{neg, s ^ {{{pw}{{neg}}}}}};',
        f'    // SHIFT: o * 2^(ka + kb - {F}), arithmetic right shifts truncate',
        "    wire [3:0] k = {1'b0, ka} + kb;              // K - 2",
        f'    wire signed [23:0] sh = $signed(o) <<< k;',
        f'    wire signed [23:0] r = sh >>> {F};',
        '    assign p = (~|ma | ~|mb) ? 16\'sd0 : r[15:0];',
        'endmodule', '']
    return '\n'.join(lines)
