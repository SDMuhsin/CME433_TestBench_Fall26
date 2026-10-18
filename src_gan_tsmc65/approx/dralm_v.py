"""Verilog of a signed 8 x 8 DR-ALM gan_mul8 (Yin et al., IEEE TSUSC 2021), bit-exact with
dralm.signed(a, b, 8, t, sign). Behavioural datapath, as in the paper (Fig. 2-3): sign
detector, leading-one detector + dynamic truncation (logarithmic converter), (k+t-2)-bit
adder with carry-in 1 and the result LSB fixed to 1 (compensation), antilogarithmic
converter + shifter, sign set, zero flag.
"""


def verilog(t, sign, header, module='gan_mul8'):
    paper = sign == 'paper'
    n = 7 if paper else 8                      # magnitude (core operand) width
    kw = 3                                     # leading-one position 0..n-1
    f = t - 1                                  # mantissa bits incl. the forced 1
    ew = kw + 1                                # exponent of the sum, 0..2n-1
    pw = 2 * n                                 # magnitude product width
    pre = f'dralm_t{t}{"" if paper else "e"}'
    if paper:
        mag = ['    // sign detector: |x| ~ ~x | 1 for x < 0 (one\'s complement, LSB OR-ed with 1)',
               '    wire [6:0] ma = (a[6:0] ^ {7{a[7]}}) | {6\'d0, a[7]};',
               '    wire [6:0] mb = (b[6:0] ^ {7{b[7]}}) | {6\'d0, b[7]};']
        out = ['    // sign set: -P ~ ~P | 1',
               '    wire [15:0] pm = {2\'b00, m};',
               '    assign p = zero ? 16\'sd0 : (neg ? $signed(~pm | 16\'d1) : $signed(pm));']
    else:
        mag = ['    // sign detector: exact two\'s-complement magnitude (|-128| = 128 fits 8 bits)',
               '    wire [7:0] ma = a[7] ? -a : a;',
               '    wire [7:0] mb = b[7] ? -b : b;']
        out = ['    // sign set: exact negation',
               '    assign p = zero ? 16\'sd0 : (neg ? -$signed(m) : $signed(m));']
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
        '    input  wire signed [7:0]  a,',
        '    input  wire signed [7:0]  b,',
        '    output wire signed [15:0] p',
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
        '    wire zero = ~|a | ~|b;',
        '    wire neg = a[7] ^ b[7];'] + out + ['endmodule', '']
    return '\n'.join(lines)
