`timescale 1ns / 1ps

// ============================================================================
// mq_hmem -- SSM state memory: 768 x 24-bit entries in 9 macros (3 triples;
// spec section 6).  Entry e: triple e[9:8], row e[7:0]; GEN_H[3t + i] holds
// byte i of triple t.  Only the addressed triple is enabled.  rdata is valid
// the cycle after an enabled read (triple select registered); triple 3 (entries
// 0x300..0x3FF) reads 0 and ignores writes.
// ============================================================================
module mq_hmem (
    input  wire        clk,
    input  wire        en,
    input  wire        we,
    input  wire [9:0]  addr,
    input  wire [23:0] wdata,
    output wire [23:0] rdata
);
    wire [1:0] triple = addr[9:8];
    reg  [1:0] triple_r;
    wire [7:0] q [0:8];

    always @(posedge clk) begin
        if (en) triple_r <= triple;
    end

    genvar gi;
    generate
        for (gi = 0; gi < 9; gi = gi + 1) begin : GEN_H
            localparam [1:0] T = gi / 3;
            mq_sram_256x8 u_sram (
                .clk   (clk),
                .ce    (en && triple == T),
                .we    (we),
                .addr  (addr[7:0]),
                .wdata (wdata[8 * (gi % 3) +: 8]),
                .rdata (q[gi])
            );
        end
    endgenerate

    assign rdata = (triple_r == 2'd3) ? 24'h000000 :
                   {q[3*triple_r + 2], q[3*triple_r + 1], q[3*triple_r]};
endmodule
