`timescale 1ns / 1ps

// ============================================================================
// mq_nlu_addr -- NLU address generation (combinational, spec section 5.1).
//
// INT32 input x + function code -> ROM word of the left grid point (idx =
// base + i), fraction f (0..2048, f / 2^11), output shift sh_fn and the exp2
// zero flag.  Fractions are truncated, never rounded.
//   sigmoid / softplus  x as Q7.8, clamped to +-2048; u = x + 2048;
//                       i = min(u >> 5, 127); f = (u - 32 i) << 6; sh = 11
//   exp2                p as Q11.19; p >= 0 -> 0; p <= -16 2^19 -> zero flag;
//                       e = p >> 19 (floor), frac = p mod 2^19,
//                       i = frac >> 14, f = (frac >> 3) & 0x7FF; sh = 10 - e
//   rsqrt               n as UINT32 Q.16, n >= 16; b = floor(log2 n);
//                       E = b - 16 rounded down to even; m16 = n 2^-E in
//                       [2^16, 2^18); u = m16 - 2^16; i = u >> 12;
//                       f = (u >> 1) & 0x7FF; sh = 16 + E / 2
// ============================================================================
module mq_nlu_addr (
    input  wire [31:0] x,
    input  wire [1:0]  fn,
    output reg  [8:0]  idx,
    output reg  [11:0] f,
    output reg  [4:0]  sh,
    output wire        zero
);
`include "mq_nlu_defs.vh"

    wire signed [31:0] xs = x;

    // ---- uniform grid [-8, 8], step 1/8 ----
    wire signed [31:0] xc    = (xs > 32'sd2048) ? 32'sd2048 : (xs < -32'sd2048) ? -32'sd2048 : xs;
    wire        [12:0] u_uni = xc[12:0] + 13'd2048;                     // 0 .. 4096
    wire        [6:0]  i_uni = u_uni[12] ? 7'd127 : u_uni[11:5];
    wire        [5:0]  r_uni = u_uni[5:0] - {i_uni[0], 5'd0} ;         // u - 32 i (0..32)
    wire        [11:0] f_uni = {r_uni, 6'd0};

    // ---- exp2 ----
    wire signed [31:0] p     = xs[31] ? xs : 32'sd0;
    wire               p_zero = (p <= -32'sd8388608);                   // p <= -16 2^19
    wire        [4:0]  e_neg = -p[23:19];                                // -e for e in -16 .. 0
    wire        [4:0]  sh_e2 = 5'd10 + e_neg;
    wire        [4:0]  i_e2  = p[18:14];
    wire        [11:0] f_e2  = {1'b0, p[13:3]};

    // ---- rsqrt ----
    reg  [4:0] b;                                                        // floor(log2 n), 4..31
    integer    j;
    always @* begin
        b = 5'd0;
        for (j = 0; j < 32; j = j + 1)
            if (x[j]) b = j[4:0];
    end
    wire        [4:0]  lsh   = 5'd31 - b;
    wire        [31:0] norm  = x << lsh;                                 // leading one at bit 31
    wire        [5:0]  e_rs  = {1'b0, b} - 6'd16;                        // E before the parity fix
    wire               odd   = e_rs[0];
    wire        [17:0] m16   = odd ? norm[31:14] : {1'b0, norm[31:15]};  // [2^16, 2^18)
    wire        [17:0] u_rs  = m16 - 18'h10000;
    wire        [5:0]  e_fix = {e_rs[5:1], 1'b0};                        // E rounded down to even
    wire        [5:0]  sh_rs = 6'd16 + {e_fix[5], e_fix[5:1]};           // 16 + E / 2

    assign zero = (fn == NLU_EXP2) & p_zero;

    always @* begin
        case (fn)
            NLU_SIGMOID, NLU_SOFTPLUS: begin
                idx = (fn == NLU_SIGMOID ? NLU_BASE_SIGMOID : NLU_BASE_SOFTPLUS) + {2'b00, i_uni};
                f   = f_uni;
                sh  = 5'd11;
            end
            NLU_EXP2: begin
                idx = NLU_BASE_EXP2 + {4'd0, i_e2};
                f   = f_e2;
                sh  = sh_e2;
            end
            default: begin
                idx = NLU_BASE_RSQRT + {3'd0, u_rs[17:12]};
                f   = {1'b0, u_rs[11:1]};
                sh  = sh_rs[4:0];
            end
        endcase
    end
endmodule
