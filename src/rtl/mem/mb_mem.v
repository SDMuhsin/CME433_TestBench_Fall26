`timescale 1ns / 1ps

// ============================================================================
// mb_mem -- on-chip FP16 word memory: PAIRS hi/lo pairs of 256x8 macros
// (spec section 6; 5 pairs = 1,280 words = 10 macros).
//   word address a: pair a[10:8], row a[7:0]; GEN_SRAM[2p] = low byte,
//   GEN_SRAM[2p + 1] = high byte of pair p.  Only the addressed pair is
//   enabled.  rdata is valid the cycle after an enabled read (pair select
//   registered); addresses beyond the last pair read 0 and ignore writes.
// ============================================================================
module mb_mem #(
    parameter integer PAIRS = 5
) (
    input  wire        clk,
    input  wire        en,
    input  wire        we,
    input  wire [10:0] addr,
    input  wire [15:0] wdata,
    output wire [15:0] rdata
);
    localparam [2:0] NPAIR = PAIRS;

    wire [2:0]  pair = addr[10:8];
    reg  [2:0]  pair_r;
    wire [7:0]  q [0:2*PAIRS-1];

    always @(posedge clk) begin
        if (en) pair_r <= pair;
    end

    genvar gi;
    generate
        for (gi = 0; gi < 2 * PAIRS; gi = gi + 1) begin : GEN_SRAM
            localparam [2:0] P = gi / 2;
            mb_sram_256x8 u_sram (
                .clk   (clk),
                .ce    (en && pair == P),
                .we    (we),
                .addr  (addr[7:0]),
                .wdata (wdata[8 * (gi % 2) +: 8]),
                .rdata (q[gi])
            );
        end
    endgenerate

    assign rdata = (pair_r < NPAIR) ? {q[2*pair_r + 1], q[2*pair_r]} : 16'h0000;
endmodule
