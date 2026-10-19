`timescale 1ns / 1ps

// gan_mul (N = 16) -> gan_mul16 wrapper: lets a fixed-width signed 16 x 16 -> 32 multiplier
// variant (module gan_mul16 (a, b, p), a = weight, b = activation) drop into the
// width-parameterised PE swap point. bench/variant.py adds this file when a variant defines
// gan_mul16; width 16 only.
module gan_mul #(
    parameter integer N = 16
) (
    input  wire signed [N-1:0]   a,
    input  wire signed [N-1:0]   b,
    output wire signed [2*N-1:0] p
);
    gan_mul16 u_mul (.a(a), .b(b), .p(p));
endmodule
