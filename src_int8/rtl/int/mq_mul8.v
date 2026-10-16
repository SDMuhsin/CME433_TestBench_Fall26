`timescale 1ns / 1ps

// ============================================================================
// mq_mul8 -- the INT8 x INT8 multiplier of mq_chip: signed 8 x 8 -> 16-bit
// product, combinational.  This is the swap point for approximate multipliers
// (docs/mul8_swap.md): every lane MAC whose side a is a streamed INT8 weight
// (all GEMV rows, the conv taps and E_out: 48,512 of the 56,198 lane steps
// per token) takes its product from here instead of the shared 24 x 17 one.
// Operand ranges in those MACs: a (weight) in [-127, 127], b (INT8
// activation) in [-128, 127].  A replacement keeps this module name and ports;
// this file is the exact reference.
// ============================================================================
module mq_mul8 (
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] p
);
    assign p = a * b;
endmodule
