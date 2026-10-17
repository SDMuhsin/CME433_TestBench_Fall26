`timescale 1ns / 1ps

// ============================================================================
// gan65_latch_rf -- DEPTH x WIDTH 1RW latch register file, a drop-in for a
// 1RW SRAM macro model (same ports, same cycle behaviour):
//   * read : rdata is registered on every enabled cycle (ce = 1) from the word
//            at addr, i.e. valid the clock after the request, held while ce = 0.
//            A read in the cycle of a write to the same word returns the OLD
//            word (read-before-write, like the macro model).
//   * write: on an enabled write cycle (ce & we at posedge N) the write data is
//            captured in wd_r; the addressed word's clock gate (one ICG per
//            word, enable = decoded ce & we & addr, latched in the ICG while
//            clk is low) opens that word's latches for the high phase after
//            posedge N; they close at the falling edge holding wd_r.  A read at
//            posedge N+1 sees the new word.
// Timing: wd_r -> latch D must settle within the high phase (SDC: zero-cycle
// setup multicycle into the latches, borrowing up to the closing edge).
// ============================================================================
module gan65_latch_rf #(
    parameter integer WIDTH = 8,
    parameter integer AW    = 8
) (
    input  wire             clk,
    input  wire             ce,
    input  wire             we,
    input  wire [AW-1:0]    addr,
    input  wire [WIDTH-1:0] wdata,
    output wire [WIDTH-1:0] rdata
);
    localparam integer DEPTH = 1 << AW;

    reg  [WIDTH-1:0] wd_r;          // write-data capture register
    reg  [WIDTH-1:0] q_r;           // read-data register
    wire [WIDTH-1:0] word [0:DEPTH-1];
    wire             wr = ce & we;

    always @(posedge clk) begin
        if (wr) wd_r <= wdata;
        if (ce) q_r  <= word[addr];
    end
    assign rdata = q_r;

    genvar r;
    generate
        for (r = 0; r < DEPTH; r = r + 1) begin : GEN_W
            wire             gclk;
            reg  [WIDTH-1:0] lat;
            gan65_icg u_icg (.clk(clk), .en(wr && addr == r), .gclk(gclk));
            always @(gclk or wd_r)
                if (gclk) lat <= wd_r;      // transparent-high latch word
            assign word[r] = lat;
        end
    endgenerate
endmodule
