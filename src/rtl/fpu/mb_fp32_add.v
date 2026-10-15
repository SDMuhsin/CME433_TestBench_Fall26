`timescale 1ns / 1ps

// ============================================================================
// mb_fp32_add -- FP32 adder, round-to-nearest-even, split into two
// combinational halves so that mb_lane can put a register between them:
//
//   mb_fp32_add_align : magnitude compare/swap, exponent difference, alignment
//                       of the smaller significand to 24 b + G + R + S (27 b)
//   mb_fp32_add_norm  : 28-bit add/sub, leading-zero count, normalise, RNE
//   mb_fp32_add_rne   : both halves back to back (single cycle; unit TB)
//
// Operand domain (spec section 3): each operand is +-0 (exp field 0) or an
// FP32 normal built from exact FP16 products / FP16 inits, so the exact
// result is 0 or >= 2^-48 in magnitude and < 2^40: no subnormal, overflow,
// Inf or NaN handling.  Exact cancellation and 0 + 0 give +0.  G/R/S
// argument: for an alignment shift d >= 2 the subtraction needs at most a
// 1-bit left normalisation; for d <= 1 the shifted-out part is exact.
// Copied from the signed-off dla_fp16_chip (fp32_add_rne.v), renamed.
// ============================================================================
module mb_fp32_add_align (
    input  wire [31:0] x,
    input  wire [31:0] y,
    output wire [23:0] m_l,      // larger significand (0 if both zero)
    output wire [26:0] m_s,      // aligned smaller significand {24 b, G, R, S}
    output wire [7:0]  e_l,      // exponent of the larger operand
    output wire        s_l,      // sign of the larger operand (= result sign)
    output wire        sub,      // effective subtraction
    output wire        z_l       // larger operand is zero (-> both zero)
);
    wire        xz   = (x[30:23] == 8'd0);
    wire        yz   = (y[30:23] == 8'd0);
    wire        swap = (y[30:0] > x[30:0]);
    wire [31:0] L    = swap ? y : x;
    wire [31:0] S    = swap ? x : y;
    wire        Lz   = swap ? yz : xz;
    wire        Sz   = swap ? xz : yz;
    wire [7:0]  d    = L[30:23] - S[30:23];
    wire [23:0] mS   = Sz ? 24'd0 : {1'b1, S[22:0]};
    // shift amounts >= 26 put the whole significand into the sticky bit
    wire [4:0]  dsh  = (d > 8'd26) ? 5'd26 : d[4:0];
    wire [49:0] sh   = {mS, 26'd0} >> dsh;

    assign m_l = Lz ? 24'd0 : {1'b1, L[22:0]};
    assign m_s = {sh[49:24], |sh[23:0]};
    assign e_l = L[30:23];
    assign s_l = L[31];
    assign sub = L[31] ^ S[31];
    assign z_l = Lz;
endmodule

module mb_fp32_add_norm (
    input  wire [23:0] m_l,
    input  wire [26:0] m_s,
    input  wire [7:0]  e_l,
    input  wire        s_l,
    input  wire        sub,
    input  wire        z_l,
    output wire [31:0] s
);
    wire [27:0] a28 = {1'b0, m_l, 3'b000};
    wire [27:0] b28 = {1'b0, m_s};
    wire [27:0] sum = sub ? (a28 - b28) : (a28 + b28);

    // leading-zero count over sum[26:0] (bit 26 is the hidden-bit position)
    reg [4:0] lz;
    integer i;
    always @* begin
        lz = 5'd27;
        for (i = 0; i < 27; i = i + 1)
            if (sum[i]) lz = 5'd26 - i[4:0];
    end

    wire        carry = sum[27];
    wire [27:0] nl    = sum << lz;
    // n = {1.f (24 b), G, R, S}
    wire [26:0] n     = carry ? {sum[27:2], sum[1] | sum[0]} : nl[26:0];
    wire [8:0]  en    = carry ? ({1'b0, e_l} + 9'd1) : ({1'b0, e_l} - {4'd0, lz});
    wire        up    = n[2] & (n[1] | n[0] | n[3]);           // RNE
    wire [24:0] mr    = {1'b0, n[26:3]} + {24'd0, up};
    wire [8:0]  ef    = en + {8'd0, mr[24]};
    wire [22:0] ff    = mr[24] ? mr[23:1] : mr[22:0];

    assign s = (z_l || sum == 28'd0) ? 32'h0000_0000 : {s_l, ef[7:0], ff};
endmodule

module mb_fp32_add_rne (
    input  wire [31:0] x,
    input  wire [31:0] y,
    output wire [31:0] s
);
    wire [23:0] m_l;
    wire [26:0] m_s;
    wire [7:0]  e_l;
    wire        s_l, sub, z_l;
    mb_fp32_add_align u_al (.x(x), .y(y), .m_l(m_l), .m_s(m_s), .e_l(e_l), .s_l(s_l), .sub(sub), .z_l(z_l));
    mb_fp32_add_norm  u_nm (.m_l(m_l), .m_s(m_s), .e_l(e_l), .s_l(s_l), .sub(sub), .z_l(z_l), .s(s));
endmodule
