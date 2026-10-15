`timescale 1ns / 1ps

// ============================================================================
// mq_mul24x17 -- signed 24 x 17 -> exact 41-bit product, the one multiplier
// of mq_chip (mq_dp).  Used as 24 x 16 by the lane (side a x sign-extended
// side b, spec 4.1) and, when the lane is not issuing, by the writeback for
// the two halves of acc x M (spec 4.2; M is unsigned 16 b, hence bit 17).
// Combinational; its product is registered by mq_lane S1 or mq_wb.
// ============================================================================
module mq_mul24x17 (
    input  wire signed [23:0] a,
    input  wire signed [16:0] b,
    output wire signed [40:0] p
);
    assign p = a * b;
endmodule
