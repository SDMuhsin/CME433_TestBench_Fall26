`timescale 1ns / 1ps

// example_trunc4 -- template for a student gan_mul8 variant (not a proposed design): the exact
// signed 8 x 8 product with its 4 least significant bits forced to zero, i.e. a crude
// truncated multiplier.  Same module name and ports as rtl/pe/gan_mul8.v; benchmark it with
//   src_gan_tsmc65/bench/run_bench.sh example_trunc4
module gan_mul8 (
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] p
);
    wire signed [15:0] exact = a * b;
    assign p = {exact[15:4], 4'b0000};
endmodule
