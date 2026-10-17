`timescale 1ns / 1ps

// gan_mul8 -> mq_mul8 adapter: lets the signed 8 x 8 multiplier variants written for
// mq_chip (src_int8/bench/variants/, module mq_mul8, same a/b/p ports and operand roles:
// a = weight, b = activation) drop into the GAN PE unchanged.  bench/variant.py adds this
// file automatically when a variant defines mq_mul8 instead of gan_mul8.
module gan_mul8 (
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] p
);
    mq_mul8 u_mul (.a(a), .b(b), .p(p));
endmodule
