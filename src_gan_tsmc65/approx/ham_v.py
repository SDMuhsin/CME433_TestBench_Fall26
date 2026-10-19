"""Verilog of a signed w x w HAM (Shi et al., IEEE TVLSI 2025), bit-exact with ham.signed for
an HnC configuration: the 8-bit H7C0 HAM-A/B/C gan_mul8 and the 16-bit H9C1 family (C1 carry,
bring-in carry truncation, -SP / -SO segment outputs). Behavioural datapath as in the paper
(Fig. 3): magnitude extraction (PACC, one's complement or exact), leading-one detector +
exponent / mantissa conversion, mixed PWL (X1..X4, zone select, three-term adder with the zone
bias), sign compensation (bias - 1 LSB of p1 plus the vacant carry bit ~sign at that LSB, then
one's complement), shift by K (truncating or BCT), output segment, zero flag.
"""
import numpy as np

from . import ham


def _me(x, me, w=8):
    h, t = w - 2, w - 1
    if me == 'pacc':
        return [f"    // ME, partial complement: ~{x}[{h}:4] and ~{x}[3:0] + 1 without carry out",
                f'    wire [{h}:0] i{x} = ~{x}[{h}:0];',
                f"    wire [3:0] l{x} = i{x}[3:0] + 4'd1;",
                f'    wire [{h}:0] m{x} = {x}[{t}] ? {{i{x}[{h}:4], l{x}}} : {x}[{h}:0];']
    if me == 'oc':
        return [f"    // ME, one's complement: ~{x}[{h}:0] for {x} < 0",
                f'    wire [{h}:0] m{x} = {x}[{t}] ? ~{x}[{h}:0] : {x}[{h}:0];']
    return [f"    // ME, exact two's-complement magnitude (|-{1 << t}| = {1 << t} needs {w} bits)",
            f'    wire [{t}:0] m{x} = {x}[{t}] ? -{x} : {x};']


def _sum_bits(h):
    """Bits of the PWL three-term sum (F fraction bits) over all mantissa pairs."""
    f = np.arange(1 << h.F)
    f1, f2 = (v.ravel() for v in np.meshgrid(f, f))
    full = h.with_(n=h.F + 2, c=0)                       # same F, nothing dropped (q = F)
    return int(ham.p1_pwl(full, f1, f2).max()).bit_length()


def _align(v, h):
    return v << (h.F - h.bf) if h.F >= h.bf else v >> (h.bf - h.F)


def _shift_out(h, w):
    """Lines after the arithmetic shift r = o * 2^(k - q): BCT, segment output, zero flag."""
    q, ow = h.q, 2 * w
    lines = []
    res = 'r'
    if h.bct:
        lines += [f'    // BCT: last two kept bits A, B -> A | B C, (B ^ C) | A C, C = first dropped bit',
                  f'    wire c = sh[{q - 1}];',
                  "    wire na = r[1] | (r[0] & c);",
                  "    wire nb = (r[0] ^ c) | (r[1] & c);",
                  f'    wire [{ow - 1}:0] rb = {{r[{ow - 1}:2], na, nb}};']
        res = 'rb'
    if h.out != 'full':
        keep = f"{{{res}[{ow - 1}:{w - 1}], {w - 1}'d0}}"
        other = f"{ow}'d0" if h.out == 'so' else f'{res}[{ow - 1}:0]'
        lines += [f'    // segment output ({h.out.upper()}): K >= {w} keeps the upper {w + 1} bits, else '
                  + ('0' if h.out == 'so' else 'the full product'),
                  f'    wire big = k >= {w - 2};',
                  f'    wire [{ow - 1}:0] v = big ? {keep} : {other};']
        res = 'v'
    lines.append(f"    assign p = (~|ma | ~|mb) ? {ow}'sd0 : {res}[{ow - 1}:0];")
    return lines


def verilog(h, name, header, module='gan_mul8'):
    """h: ham.Ham of type HnC (m = 0) with sign compensation."""
    assert h.m == 0 and h.signed and h.mts == 'sc' and h.loa == 'both'
    w = h.w
    mw = w if h.me == 'exact' else w - 1           # magnitude bits
    kw = (mw - 1).bit_length()                     # leading-one position 0..mw-1
    F, q = h.F, h.q                                # mantissa / p1 fraction bits
    d = F - q                                      # sum bits dropped (C1: 1)
    ps = _sum_bits(h)                              # PWL sum bits
    pw = ps - d                                    # p1_PWL bits
    z1, z5, z2, z4 = h.zones
    b = [_align(v, h) - (1 << d) for v in h.biases]  # sign compensation: biases - 1 LSB of p1
    x2, x3 = h.x2b, h.x3b
    x4b = h.x4b or F
    x4mask = ((1 << x4b) - 1) << (F - x4b)
    shw = 3 * w                                    # o << k fits: pw + 1 + 2 (mw - 1) bits
    carry = f"{{{ps - 1}'d0, ~neg}}" if d == 0 else f"{{{ps - 1 - d}'d0, ~neg, {d}'d0}}"
    if d == 0:
        sum_lines = [f'    assign s = t1 + t2 + bias + {carry};   // vacant carry bit = ~sign']
    else:
        sum_lines = [f'    wire [{ps - 1}:0] sd = t1 + t2 + bias + {carry};   // vacant carry bit = ~sign',
                     f'    assign s = sd[{ps - 1}:{d}];                      // C{d}: low {d} sum bit(s) dropped']
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
        f'// mixed PWL fit of (1 + f1)(1 + f2) in units of 2^-{q}, sign compensated: the result is',
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
        f"    wire [{F - 1}:0] x4 = (x2[{x2}] ? f1 : f2) & {F}'b{x4mask:0{F}b};   // min(f1, f2), {x4b} MSBs",
        f'    wire zn1 = x3 < {z1};',
        f'    wire zn5 = x3 >= {z5};',
        f'    wire zn2 = ~zn1 & ~zn5 & (ax2 <= {z2});',
        f'    wire zn4 = ~zn1 & ~zn5 & (ax2 >= {z4});',
        f'    wire [{ps - 1}:0] t1 = zn5 ? {{x1, 1\'b0}} : {{1\'b0, x1}};',
        f'    wire [{ps - 1}:0] t2 = zn1 ? x4 >> 2 : zn4 ? x4 : zn5 ? -(x1 >> 4) : x1 >> 1;',
        f"    wire [{ps - 1}:0] bias = zn1 ? {ps}'d{b[0]} : zn5 ? {ps}'d{b[4]} : zn2 ? {ps}'d{b[1]} :",
        f"                        zn4 ? {ps}'d{b[3]} : {ps}'d{b[2]};"] + sum_lines + [
        'endmodule',
        '',
        f'module {module} (',
        f'    input  wire signed [{w - 1}:0]  a,',
        f'    input  wire signed [{w - 1}:0]  b,',
        f'    output wire signed [{2 * w - 1}:0] p',
        ');'] + _me('a', h.me, w) + _me('b', h.me, w) + [
        f'    wire [{kw - 1}:0] ka, kb;',
        f'    wire [{F - 1}:0] fa, fb;',
        f'    {name}_emc u_ea (.x(ma), .k(ka), .f(fa));',
        f'    {name}_emc u_eb (.x(mb), .k(kb), .f(fb));',
        f'    wire neg = a[{w - 1}] ^ b[{w - 1}];',
        f'    wire [{pw - 1}:0] s;',
        f'    {name}_pwl u_pwl (.f1(fa), .f2(fb), .neg(neg), .s(s));',
        '    // MTS: one\'s complement of the compensated result (= -p1 for a negative product)',
        f'    wire signed [{pw}:0] o = {{neg, s ^ {{{pw}{{neg}}}}}};',
        f'    // SHIFT: o * 2^(ka + kb - {q}), arithmetic right shifts truncate',
        f"    wire [{kw}:0] k = {{1'b0, ka}} + kb;              // K - 2",
        f'    wire signed [{shw - 1}:0] sh = $signed(o) <<< k;',
        f'    wire signed [{shw - 1}:0] r = sh >>> {q};'] + _shift_out(h, w) + [
        'endmodule', '']
    return '\n'.join(lines)
