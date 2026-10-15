`timescale 1ns / 1ps

// ============================================================================
// mb_agu -- address generator: addr = base + (am.k ? k : 0) + (am.d ? d * (am.d4 ? 4 : 1) : 0).
// am bit 0 = +k (level-0 counter), bit 1 = +d (level-1 counter), bit 2 = d x 4.
// 11-bit word address into the 5-pair FP16 memory (combinational).
// ============================================================================
module mb_agu (
    input  wire [10:0] base,
    input  wire [2:0]  am,
    input  wire [7:0]  k,
    input  wire [7:0]  d,
    output wire [10:0] addr
);
    wire [10:0] off_k = am[0] ? {3'd0, k} : 11'd0;
    wire [10:0] off_d = !am[1] ? 11'd0 : am[2] ? {1'b0, d, 2'b00} : {3'd0, d};

    assign addr = base + off_k + off_d;
endmodule
