`timescale 1ns / 1ps
// Standalone multiplier bench: input registers -> mul_core (N x N -> 2N) -> output register, so
// the a -> p path is register to register. The width is the single parameter N, set from the
// macro MUL_N (DC / Formality / VCS: +define+MUL_N=8|16; default 16). mul_core is one of the
// generated designs in rtl/w<N>/ (approx/mulbench.py).
`ifndef MUL_N
`define MUL_N 16
`endif
module mul_bench #(
    parameter N = `MUL_N
) (
    input  wire             clk,
    input  wire [N - 1:0]     a,
    input  wire [N - 1:0]     b,
    output reg  [2 * N - 1:0] p
);
    reg  [N - 1:0] a_q, b_q;
    wire [2 * N - 1:0] m;
    mul_core u_mul (.a(a_q), .b(b_q), .p(m));
    always @(posedge clk) begin
        a_q <= a;
        b_q <= b;
        p   <= m;
    end
endmodule
