`timescale 1ns / 1ps

// ============================================================================
// mq_sram_256x8 -- 65 nm override of src_int8/rtl/mem/mq_sram_256x8.v:
// same module name and ports, the GF180 SRAM macro replaced by a 256 x 8
// latch register file (mq65_latch_rf).  mq_hmem / mq_bmem are unchanged.
// ============================================================================
module mq_sram_256x8 (
    input  wire       clk,
    input  wire       ce,
    input  wire       we,
    input  wire [7:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata
);
    mq65_latch_rf #(.WIDTH(8), .AW(8)) u_rf (
        .clk   (clk),
        .ce    (ce),
        .we    (we),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );
endmodule
