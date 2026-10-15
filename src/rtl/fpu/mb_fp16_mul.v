`timescale 1ns / 1ps

// ============================================================================
// mb_fp16_mul -- FP16 x FP16 -> exact FP32 product (combinational).
//
// Spec section 3: the product of two canonical FP16 values is exact in FP32
// ({1.ma} x {1.mb} has at most 22 significant bits; |p| in [2^-28, 2^32]).
// Operand canonicalisation (defensive; on-chip words are canonical already):
//   exp == 0  -> +0 (FTZ; subnormals and -0 count as zero)
//   exp == 31 -> +-65504 (no Inf/NaN on chip)
// A zero operand gives +0 (32'h0).  Copied from the signed-off dla_fp16_chip.
// ============================================================================
module mb_fp16_mul (
    input  wire [15:0] a,
    input  wire [15:0] b,
    output wire [31:0] p
);
    wire       za    = (a[14:10] == 5'd0);
    wire       zb    = (b[14:10] == 5'd0);
    wire       sat_a = (a[14:10] == 5'd31);
    wire       sat_b = (b[14:10] == 5'd31);
    wire [4:0] ea    = sat_a ? 5'd30 : a[14:10];
    wire [4:0] eb    = sat_b ? 5'd30 : b[14:10];
    wire [9:0] ma    = sat_a ? 10'h3FF : a[9:0];
    wire [9:0] mb    = sat_b ? 10'h3FF : b[9:0];

    wire [21:0] pm  = {1'b1, ma} * {1'b1, mb};
    wire [7:0]  e32 = {3'b000, ea} + {3'b000, eb} + 8'd97 + {7'd0, pm[21]};
    wire [22:0] f32 = pm[21] ? {pm[20:0], 2'b00} : {pm[19:0], 3'b000};

    assign p = (za | zb) ? 32'h0000_0000 : {a[15] ^ b[15], e32, f32};
endmodule
