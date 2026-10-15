`timescale 1ns / 1ps

// ============================================================================
// mb_nlu_addr -- NLU address generation (combinational, spec section 4).
//
// FP16 x + function code -> ROM word of the left grid point (idx = base + i),
// fraction q (f = q / 2^11, q in 0..2048), output scale s, softplus bypass.
// All arithmetic is exact fixed point on |x| * 2^16 (floor M + sticky st):
//   uniform  sigmoid/softplus, grid [-8, 8] step 1/8:
//            U = floor((clamp(x) + 8) * 2^14);  x >= 8 -> U = 2^18 (i 127, q 2048)
//   exp2     P = floor(min(x, 0) * 2^16) = -ceil(|x| * 2^16):
//            low 16 b = (i, q), P >> 16 = floor(p) = s, clamped to -128
//   rsqrt    x = m 2^e, m in [1, 4), e even: U = (m - 1) * 2^15, s = -e / 2
//            (x must be > 0; other inputs give an unspecified result)
// For uniform and rsqrt, i = U >> 11 and q = U mod 2^11.
// ============================================================================
module mb_nlu_addr (
    input  wire [15:0]       x,
    input  wire [1:0]        fn,
    output reg  [8:0]        idx,
    output reg  [11:0]       q,
    output reg signed [7:0]  scale,
    output wire              byp
);
`include "mb_nlu_defs.vh"

    wire        sgn  = x[15];
    wire [4:0]  ex   = x[14:10];
    wire [10:0] mant = (ex == 5'd0) ? 11'd0 : {1'b1, x[9:0]};

    // |x| * 2^16 = mant * 2^(ex - 9)
    wire [48:0] wide = {30'd0, mant, 8'd0} << ex;
    wire [31:0] m16  = wide[48:17];
    wire        st   = |wide[16:0];

    // ---- uniform grid [-8, 8] ----
    wire        big   = (ex >= 5'd18);                           // |x| >= 8
    wire [16:0] fl14  = m16[18:2];                               // floor(|x| 2^14)
    wire [16:0] ce14  = fl14 + {16'd0, (|m16[1:0]) | st};        // ceil(|x| 2^14)
    wire [18:0] u_uni = big ? (sgn ? 19'd0 : 19'h40000) :
                        sgn ? (19'h20000 - {2'b00, ce14}) : (19'h20000 + {2'b00, fl14});
    wire        top   = u_uni[18];                               // u = 128 (x >= 8)
    wire [6:0]  i_uni = top ? 7'd127 : u_uni[17:11];
    wire [11:0] q_uni = top ? 12'd2048 : {1'b0, u_uni[10:0]};

    // ---- exp2: p = min(x, 0) ----
    wire [32:0] ce16  = {1'b0, m16} + {32'd0, st};               // ceil(|x| 2^16)
    wire [32:0] p16   = sgn ? (33'd0 - ce16) : 33'd0;            // floor(p 2^16)
    wire        uflow = p16[32] & (p16[31:23] != 9'h1FF);        // floor(p) < -128
    wire [7:0]  s_e2  = uflow ? 8'h80 : p16[23:16];

    // ---- rsqrt: biased ex odd <=> unbiased exponent even ----
    wire [16:0] u_rs  = ex[0] ? {2'b00, x[9:0], 5'd0} : ({1'b0, x[9:0], 6'd0} + 17'h08000);
    wire [5:0]  d_rs  = 6'd16 - {1'b0, ex};                      // 16 - ex, signed
    wire [7:0]  s_rsq = {{3{d_rs[5]}}, d_rs[5:1]};               // floor((16 - ex) / 2)

    always @* begin
        case (fn)
            NLU_SIGMOID, NLU_SOFTPLUS: begin
                idx   = (fn == NLU_SIGMOID ? NLU_BASE_SIGMOID : NLU_BASE_SOFTPLUS) + {2'b00, i_uni};
                q     = q_uni;
                scale = 8'sd0;
            end
            NLU_EXP2: begin
                idx   = NLU_BASE_EXP2 + {4'd0, p16[15:11]};
                q     = {1'b0, p16[10:0]};
                scale = s_e2;
            end
            default: begin                                       // NLU_RSQRT
                idx   = NLU_BASE_RSQRT + {3'd0, u_rs[16:11]};
                q     = {1'b0, u_rs[10:0]};
                scale = s_rsq;
            end
        endcase
    end

    assign byp = (fn == NLU_SOFTPLUS) & big & !sgn;
endmodule
