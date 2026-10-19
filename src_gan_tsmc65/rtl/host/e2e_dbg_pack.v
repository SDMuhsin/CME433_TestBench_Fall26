`timescale 1ns / 1ps

// ============================================================================
// e2e_dbg_pack -- raw debug writes (DBG_WR_A / DBG_WR_B) of DATA_W = 8*NB bit
// A/B elements from the host's byte writes.  The host byte address h_addr
// (auto-incremented per byte) holds element h_addr / NB, byte h_addr % NB,
// little endian; the element is written to the DLA when its last byte
// arrives (the earlier bytes are held here).  NB = 1 (8-bit chip): wires.
// NB must be a power of two.
// ============================================================================
module e2e_dbg_pack #(
    parameter integer NB = 1
) (
    input  wire            clk,
    input  wire            wr_en,       // one host byte write (h_addr = its address)
    input  wire [15:0]     h_addr,
    input  wire [7:0]      wr_byte,
    output wire            el_we,       // element write strobe
    output wire [9:0]      el_addr,     // element address (A: {row, k}, B: {k, col})
    output wire [8*NB-1:0] el_data
);
    generate
        if (NB == 1) begin : G_BYTE
            assign el_we   = wr_en;
            assign el_addr = h_addr[9:0];
            assign el_data = wr_byte;
            wire _unused = &{1'b0, clk, h_addr[15:10]};
        end else begin : G_WORD
            localparam integer BL = $clog2(NB);
            localparam [BL-1:0] B_LAST = NB - 1;
            reg [7:0] hold [0:NB-2];
            integer i;
            always @(posedge clk)
                if (wr_en && h_addr[BL-1:0] != B_LAST) hold[h_addr[BL-1:0]] <= wr_byte;
            assign el_we   = wr_en && (h_addr[BL-1:0] == B_LAST);
            assign el_addr = h_addr[BL+9:BL];
            reg [8*NB-9:0] lo;
            always @* for (i = 0; i < NB - 1; i = i + 1) lo[8*i +: 8] = hold[i];
            assign el_data = {wr_byte, lo};
        end
    endgenerate
endmodule
