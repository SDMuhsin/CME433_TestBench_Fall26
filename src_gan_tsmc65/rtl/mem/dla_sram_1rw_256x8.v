`timescale 1ns / 1ps

// ============================================================================
// dla_sram_1rw_256x8 -- 65 nm override of rtl/gf180_sram_1rw_256x8.v: same
// module name and ports, the GF180 256x8 SRAM macro replaced by a 256 x 8
// latch register file (gan65_latch_rf).  The legacy wrapper ties the macro's
// chip enable on (CEN = 0), so the macro reads addr on every clock; the RF is
// therefore instantiated with ce = 1 and has the same cycle behaviour
// (registered read, read-before-write).  dla_a/b_buffer_bank are unchanged.
// ============================================================================
module dla_sram_1rw_256x8 (
    input  wire       clk,
    input  wire       we,
    input  wire [7:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata
);
    gan65_latch_rf #(.WIDTH(8), .AW(8)) u_rf (
        .clk   (clk),
        .ce    (1'b1),
        .we    (we),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );
endmodule
