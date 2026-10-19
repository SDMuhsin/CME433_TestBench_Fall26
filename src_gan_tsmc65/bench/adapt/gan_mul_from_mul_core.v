`timescale 1ns / 1ps

// gan_mul -> mul_core wrapper: lets a multiplier of the standalone multiplier bench
// (syn/mulbench/rtl/w<N>/<design>.v, module mul_core, N x N -> 2N, a = weight, b = activation)
// drop into the PE swap point unchanged. bench/variant.py adds this file for `mb:<design>`
// variants, whose width must equal the chip's; only signed designs fit the signed datapath.
module gan_mul #(
    parameter integer N = 16
) (
    input  wire signed [N-1:0]   a,
    input  wire signed [N-1:0]   b,
    output wire signed [2*N-1:0] p
);
    mul_core u_mul (.a(a), .b(b), .p(p));
endmodule
