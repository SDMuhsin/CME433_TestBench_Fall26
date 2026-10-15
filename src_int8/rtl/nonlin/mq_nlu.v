`timescale 1ns / 1ps

// ============================================================================
// mq_nlu -- shared nonlinear unit (sigmoid, softplus, exp2, rsqrt; spec 5.1).
// It supplies operands to mq_lane, which does the interpolation:
//
//   Sigma = T[i] (2^11 - f) + T[i+1] f      two lane steps, ps 0, init 0
//   out   = zero ? 0 : sat_16(rsh(Sigma, sh_fn))   (mq_wb, SH mode, width 16)
//
//   cycle 0     ld: register idx / f / sh / zero of (fn, x)
//   step = 0    (a, b) = (T[i],   2^11 - f)   -> issue with first = 1, init = 0
//   step = 1    (a, b) = (T[i+1], f)          -> issue 2+ cycles later
// Outputs hold until the next ld.  `a` is unsigned 16 b (zero-extend on
// side a), `b` is 0..2048 (zero-extend on side b).
// ============================================================================
module mq_nlu (
    input  wire        clk,
    input  wire        ld,
    input  wire [1:0]  fn,
    input  wire [31:0] x,
    input  wire        step,
    output wire [15:0] a,
    output wire [11:0] b,
    output reg  [4:0]  sh,
    output reg         zero
);
    wire [8:0]  idx;
    wire [11:0] f;
    wire [4:0]  s;
    wire        z;
    mq_nlu_addr u_addr (.x(x), .fn(fn), .idx(idx), .f(f), .sh(s), .zero(z));

    reg [8:0]  idx_r;
    reg [11:0] f_r;
    always @(posedge clk) begin
        if (ld) begin
            idx_r <= idx; f_r <= f; sh <= s; zero <= z;
        end
    end

    mq_nlu_rom u_rom (.addr(idx_r + {8'd0, step}), .t(a));
    assign b = step ? f_r : (12'd2048 - f_r);
endmodule
