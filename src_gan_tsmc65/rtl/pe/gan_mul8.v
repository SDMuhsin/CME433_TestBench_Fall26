`timescale 1ns / 1ps

// ============================================================================
// gan_mul8 -- fixed-width INT8 x INT8 exact multiplier: signed 8 x 8 -> 16-bit
// product, combinational.  The template of the 8-bit approximate-multiplier
// variants (bench/variants/, docs/bench.md).  The chip instantiates gan_mul
// (pe/gan_mul.v, parameterised by the datapath width); bench/variant.py wraps a
// gan_mul8 variant with bench/adapt/gan_mul_from_gan_mul8.v at width 8.
//   a : weight      (A buffer), int8 in [-128, 127]
//   b : activation  (B buffer), int8: latent zq in [-127, 127], hidden h0/h2
//                   in [0, 127]
// A replacement keeps this module name and ports.
// ============================================================================
module gan_mul8 (
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] p
);
    assign p = a * b;
endmodule
