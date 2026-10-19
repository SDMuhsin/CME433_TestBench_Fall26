"""Verilog of an n x n DR-ALM (Yin et al., IEEE TSUSC 2021): the signed gan_mul8 (n = 8),
bit-exact with dralm.signed(a, b, n, t, sign), or with sign='none' the unsigned core,
bit-exact with dralm.unsigned(a, b, n, t). Behavioural datapath, as in the paper (Fig. 2-3):
sign detector, leading-one detector + dynamic truncation (logarithmic converter), (k+t-2)-bit
adder with carry-in 1 and the result LSB fixed to 1 (compensation), antilogarithmic
converter + shifter, sign set, zero flag.
"""


def _sign_units(sign, n):
    """(magnitude lines, output lines) of the sign detector / sign set; w = 2n output bits."""
    w, h = 2 * n, n - 1
    if sign == 'none':
        return (['    // unsigned operands: no sign units',
                 f'    wire [{h}:0] ma = a;',
                 f'    wire [{h}:0] mb = b;'],
                [f"    assign p = zero ? {w}'d0 : m;"])
    if sign == 'paper':
        return ([f'    // sign detector: |x| ~ ~x | 1 for x < 0 (one\'s complement, LSB OR-ed with 1)',
                 f"    wire [{h - 1}:0] ma = (a[{h - 1}:0] ^ {{{h}{{a[{h}]}}}}) | {{{h - 1}'d0, a[{h}]}};",
                 f"    wire [{h - 1}:0] mb = (b[{h - 1}:0] ^ {{{h}{{b[{h}]}}}}) | {{{h - 1}'d0, b[{h}]}};"],
                ['    // sign set: -P ~ ~P | 1',
                 f"    wire [{w - 1}:0] pm = {{2'b00, m}};",
                 f"    assign p = zero ? {w}'sd0 : (neg ? $signed(~pm | {w}'d1) : $signed(pm));"])
    return ([f"    // sign detector: exact two's-complement magnitude (|-{1 << h}| = {1 << h} fits {n} bits)",
             f'    wire [{h}:0] ma = a[{h}] ? -a : a;',
             f'    wire [{h}:0] mb = b[{h}] ? -b : b;'],
            ['    // sign set: exact negation',
             f"    assign p = zero ? {w}'sd0 : (neg ? -$signed(m) : $signed(m));"])


def verilog(t, sign, header, module='gan_mul8', n_op=8):
    """sign: 'paper' | 'exact' (signed) or 'none' (unsigned core); n_op = operand bits."""
    paper = sign == 'paper'
    n = n_op - 1 if paper else n_op           # magnitude (core operand) width
    kw = (n - 1).bit_length()                  # leading-one position 0..n-1
    f = t - 1                                  # mantissa bits incl. the forced 1
    ew = kw + 1                                # exponent of the sum, 0..2n-1
    pw = 2 * n                                 # magnitude product width
    w = 2 * n_op                               # output width
    pre = f'dralm_t{t}{"" if paper else "e" if sign == "exact" else "u"}'
    if n_op != 8:
        pre += f'_{n_op}'
    mag, out = _sign_units(sign, n_op)
    s = '' if sign == 'none' else 'signed '
    hs = n_op - 1
    frac = (f'xs[{n - 2}:{n - t + 1}], 1\'b1' if t - 2 > 0 else "1'b1")
    lines = ['`timescale 1ns / 1ps', ''] + [f'// {h}' if h else '//' for h in header] + [
        '',
        f'// logarithmic converter: x (> 0) -> {{k, x_t}}, k = leading-one position, x_t = the',
        f'// {t - 2} bits after the leading one and a forced 1 (dynamic truncation, t = {t})',
        f'module {pre}_log (',
        f'    input  wire [{n - 1}:0] x,',
        f'    output wire [{kw + f - 1}:0] l',
        ');',
        f'    reg [{kw - 1}:0] k;',
        '    integer i;',
        '    always @* begin',
        '        k = 0;',
        f'        for (i = 1; i < {n}; i = i + 1)',
        '            if (x[i]) k = i;',
        '    end',
        f'    wire [{n - 1}:0] xs = x << ({n - 1} - k);       // leading one to bit {n - 1}',
        f'    assign l = {{k, {frac}}};',
        'endmodule',
        '',
        '// antilogarithmic converter + shifter: P = {1, L[t-2:0]} * 2^(L[top:t-1] - (t-1)),',
        '// bits below the binary point dropped',
        f'module {pre}_antilog (',
        f'    input  wire [{ew + f - 1}:0] l,',
        f'    output wire [{pw - 1}:0] p',
        ');',
        f'    wire [{f}:0] mant = {{1\'b1, l[{f - 1}:0]}};',
        f'    wire [{ew - 1}:0] e = l[{ew + f - 1}:{f}];',
        f'    wire [{pw + f - 1}:0] s = {{{{({pw - 1}){{1\'b0}}}}, mant}} << e;',
        f'    assign p = s[{pw + f - 1}:{f}];',
        'endmodule',
        '',
        f'module {module} (',
        f'    input  wire {s}[{hs}:0]  a,',
        f'    input  wire {s}[{hs}:0]  b,',
        f'    output wire {s}[{w - 1}:0] p',
        ');'] + mag + [
        f'    wire [{kw + f - 1}:0] la, lb;',
        f'    {pre}_log u_la (.x(ma), .l(la));',
        f'    {pre}_log u_lb (.x(mb), .l(lb));',
        '    // adder + compensation: both x_t LSBs are 1 and +2^-(t-1) is added, so the sum LSB',
        '    // is 1 and the upper bits get a carry-in of 1',
        f'    wire [{ew + f - 2}:0] hi = la[{kw + f - 1}:1] + lb[{kw + f - 1}:1] + 1\'b1;',
        f'    wire [{ew + f - 1}:0] l = {{hi, 1\'b1}};',
        f'    wire [{pw - 1}:0] m;',
        f'    {pre}_antilog u_al (.l(l), .p(m));',
        '    wire zero = ~|a | ~|b;'] + (
        [] if sign == 'none' else [f'    wire neg = a[{hs}] ^ b[{hs}];']) + out + ['endmodule', '']
    return '\n'.join(lines)
