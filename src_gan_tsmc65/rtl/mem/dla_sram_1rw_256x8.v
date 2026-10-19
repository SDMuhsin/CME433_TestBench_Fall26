`timescale 1ns / 1ps

// ============================================================================
// dla_sram_1rw_256x8 -- 65 nm override of rtl/gf180_sram_1rw_256x8.v: same
// module name and ports, the GF180 256x8 SRAM macro replaced by a 256 x 8
// latch register file (gan65_latch_rf).  The legacy wrapper ties the macro's
// chip enable on (CEN = 0), so the macro reads addr on every clock; the RF is
// therefore instantiated with ce = 1 and has the same cycle behaviour
// (registered read, read-before-write).
// W = word width = the chip's datapath width (8, or 16 for the 16-bit chip:
// a 256 x 16 RF); the module keeps the legacy 256x8 name so the 8-bit
// netlists and flow scripts are unchanged.
// ============================================================================
module dla_sram_1rw_256x8 #(
    parameter integer W = 8
) (
    input  wire         clk,
    input  wire         we,
    input  wire [7:0]   addr,
    input  wire [W-1:0] wdata,
    output wire [W-1:0] rdata
);
    gan65_latch_rf #(.WIDTH(W), .AW(8)) u_rf (
        .clk   (clk),
        .ce    (1'b1),
        .we    (we),
        .addr  (addr),
        .wdata (wdata),
        .rdata (rdata)
    );
endmodule
