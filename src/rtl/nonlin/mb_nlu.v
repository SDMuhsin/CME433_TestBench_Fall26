`timescale 1ns / 1ps

// ============================================================================
// mb_nlu -- shared nonlinear unit (sigmoid, softplus, exp2, rsqrt; spec
// section 4).  It supplies operands to mb_lane, which does the interpolation:
//
//   out = wb( T[i] * (1 - f) + T[i+1] * f , s )      (two lane steps)
//
//   cycle 0     ld: register address / fraction / scale / bypass of (fn, x)
//   step = 0    (a, b) = (T[i],   1 - f)   -> issue with first = 1, init = 0
//   step = 1    (a, b) = (T[i+1], f)       -> issue 2+ cycles later
//   result      lane y with lane scale = `scale`; `y` adds the softplus
//               bypass (x >= 8 -> x).  Outputs hold until the next ld.
// Minimum ld -> y latency with mb_lane: 6 cycles (issues in cycles 1 and 3).
// ============================================================================
module mb_nlu (
    input  wire              clk,
    input  wire              ld,
    input  wire [1:0]        fn,
    input  wire [15:0]       x,
    input  wire              step,
    output wire [15:0]       a,
    output wire [15:0]       b,
    output reg signed [7:0]  scale,
    input  wire [15:0]       lane_y,
    output wire [15:0]       y
);
    wire [8:0]        idx;
    wire [11:0]       q;
    wire signed [7:0] s;
    wire              byp;
    mb_nlu_addr u_addr (.x(x), .fn(fn), .idx(idx), .q(q), .scale(s), .byp(byp));

    reg [8:0]  idx_r;
    reg [11:0] q_r;
    reg [15:0] x_r;
    reg        byp_r;
    always @(posedge clk) begin
        if (ld) begin
            idx_r <= idx; q_r <= q; scale <= s; byp_r <= byp; x_r <= x;
        end
    end

    mb_nlu_rom  u_rom  (.addr(idx_r + {8'd0, step}), .t(a));
    mb_nlu_frac u_frac (.q(step ? q_r : 12'd2048 - q_r), .h(b));

    assign y = byp_r ? x_r : lane_y;
endmodule
