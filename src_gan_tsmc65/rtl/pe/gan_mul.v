`timescale 1ns / 1ps

// ============================================================================
// gan_mul -- the N x N multiplier of every processing element of the GAN
// accelerator (16 PEs in dla_pe_array): signed N x N -> 2N-bit product,
// combinational, N = the chip's datapath width (rtl/cfg/w<N>, 8 or 16).
// This is the swap point for approximate multipliers (bench/variants/,
// docs/bench.md, docs/width16.md): every MAC of all three generator layers
// takes its product from here.
//   a : weight      (A buffer), signed N bit
//   b : activation  (B buffer), signed N bit: latent zq in [-(2^(N-1)-1), 2^(N-1)-1],
//                   hidden h0/h2 in [0, 2^(N-1)-1]
// A replacement defines this module (any N), or a fixed-width gan_mul8 /
// gan_mul16 (a, b, p) that bench/variant.py wraps with bench/adapt/; this
// file is the exact reference.
// ============================================================================
module gan_mul #(
    parameter integer N = 8
) (
    input  wire signed [N-1:0]   a,
    input  wire signed [N-1:0]   b,
    output wire signed [2*N-1:0] p
);
    assign p = a * b;
endmodule
