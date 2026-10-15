`timescale 1ns / 1ps

// ============================================================================
// mb_fp16_to_fp32 -- exact FP16 -> FP32 conversion (combinational).
//
// Used for the accumulator init operand (bias / residual / constant, spec
// section 3).  Same canonicalisation as mb_fp16_mul: exp 0 -> +0 (also -0),
// exp 31 -> +-65504.  Otherwise exponent + 112, fraction << 13.
// ============================================================================
module mb_fp16_to_fp32 (
    input  wire [15:0] h,
    output wire [31:0] f
);
    wire       zero = (h[14:10] == 5'd0);
    wire       sat  = (h[14:10] == 5'd31);
    wire [7:0] e    = sat ? 8'd142 : ({3'b000, h[14:10]} + 8'd112);
    wire [9:0] m    = sat ? 10'h3FF : h[9:0];

    assign f = zero ? 32'h0000_0000 : {h[15], e, m, 13'd0};
endmodule
