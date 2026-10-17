`timescale 1ns / 1ps

// ============================================================================
// gan_mul8 -- the INT8 x INT8 multiplier of every processing element of the
// GAN accelerator (16 PEs in dla_pe_array): signed 8 x 8 -> 16-bit product,
// combinational.  This is the swap point for approximate multipliers
// (bench/variants/, docs/bench.md): every MAC of all three generator layers
// takes its product from here.
//   a : weight      (A buffer), int8 in [-128, 127]
//   b : activation  (B buffer), int8: latent zq in [-127, 127], hidden h0/h2
//                   in [0, 127]
// A replacement keeps this module name and ports; this file is the exact
// reference.
// ============================================================================
module gan_mul8 (
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] p
);
    assign p = a * b;
endmodule
