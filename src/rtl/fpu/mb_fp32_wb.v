`timescale 1ns / 1ps

// ============================================================================
// mb_fp32_wb -- lane writeback wb(acc, s) (combinational, spec section 3).
//
//   v = acc * 2^s                    exact exponent add, s signed 8 b
//   |v| < 2^-14 (or acc == 0) -> +0  FTZ before rounding, never -0
//   else RNE to 10 fraction bits;    rounded magnitude > 65504 -> +-65504
//
// acc is an FP32 normal or zero (the lane never produces subnormals, Inf or
// NaN).  The NLU clamps its exp2 scale to -128, which is bit-exact because
// the interpolated value is <= 2 and 2 * 2^-128 flushes to zero anyway.
// ============================================================================
module mb_fp32_wb (
    input  wire [31:0]       acc,
    input  wire signed [7:0] scale,
    output wire [15:0]       y
);
    wire              zero = (acc[30:23] == 8'd0);
    // biased FP32 exponent of v; range -128 .. 382 fits 10 b signed
    wire signed [9:0] ev   = $signed({2'b00, acc[30:23]}) + {{2{scale[7]}}, scale};
    wire              tiny = zero | (ev < 10'sd113);
    wire              up   = acc[12] & ((|acc[11:0]) | acc[13]);   // RNE
    wire [10:0]       mr   = {1'b0, acc[22:13]} + {10'd0, up};
    wire signed [9:0] e16  = ev - 10'sd112 + $signed({9'd0, mr[10]});
    wire              ovf  = (e16 > 10'sd30);

    assign y = tiny ? 16'h0000 :
               ovf  ? {acc[31], 15'h7BFF} :
                      {acc[31], e16[4:0], mr[9:0]};
endmodule
