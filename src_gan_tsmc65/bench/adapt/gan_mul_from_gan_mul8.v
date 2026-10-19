`timescale 1ns / 1ps

// gan_mul (N = 8) -> gan_mul8 wrapper: lets the fixed-width signed 8 x 8 multiplier variants
// (module gan_mul8, bench/variants/*.v) drop into the width-parameterised PE swap point.
// bench/variant.py adds this file when a variant defines gan_mul8; width 8 only.
module gan_mul #(
    parameter integer N = 8
) (
    input  wire signed [N-1:0]   a,
    input  wire signed [N-1:0]   b,
    output wire signed [2*N-1:0] p
);
    gan_mul8 u_mul (.a(a), .b(b), .p(p));
endmodule
