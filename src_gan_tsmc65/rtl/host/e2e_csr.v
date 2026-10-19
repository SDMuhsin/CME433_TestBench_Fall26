`timescale 1ns / 1ps

// ============================================================================
// e2e_csr -- byte-addressed control/status registers of dla_e2e_chip.
//
//   0x00       ID = 0xE2 (RO)
//   0x01       CTRL: [0] soft_reset_seq, [1] pe_col_gate_en (reserved, no
//              effect in v1), [2] quad_en (STREAM_Q nibble mode; reset 1)
//   0x02       STATUS (RO): [0] busy (image in flight), [1] done, [2] hrdy,
//              [3] err_cmd, [4] err_overflow, [6:5] layer
//   0x03-0x05  stream byte count (RO, BC_W b, little endian; 19 b on the 8-bit
//              chip, 20 b on the 16-bit chip)
//   0x06       tile (RO)
//   0x10-0x27  six 32-bit requant multipliers, little endian, reset to the
//              G300 constants of the datapath width (rtl/cfg/w<W>/g300_quant_params.vh):
//              MA0 0x10, MB0 0x14, MA2 0x18, MB2 0x1C, MW4 0x20, MB4 0x24
// Unmapped addresses read 0x00; writes to RO/unmapped addresses are ignored.
// ============================================================================
module e2e_csr #(
    parameter integer BC_W = 19                // stream byte counter width (<= 24)
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,
    input  wire [7:0]  addr,
    input  wire [7:0]  wdata,
    output reg  [7:0]  rdata,

    // status inputs
    input  wire        st_busy,
    input  wire        st_done,
    input  wire        st_hrdy,
    input  wire        st_err_cmd,
    input  wire        st_err_ovf,
    input  wire [1:0]  st_layer,
    input  wire [BC_W-1:0] st_byte_cnt,
    input  wire [7:0]  st_tile,

    output wire        soft_rst,
    output wire        pe_col_gate_en,
    output wire        quad_en,
    output reg  [31:0] ma0,
    output reg  [31:0] mb0,
    output reg  [31:0] ma2,
    output reg  [31:0] mb2,
    output reg  [31:0] mw4,
    output reg  [31:0] mb4
);
    `include "g300_quant_params.vh"

    localparam [7:0]  ID_VAL    = 8'hE2;
    localparam [2:0]  CTRL_RST  = 3'b100;
    localparam [31:0] RST_MA0 = G300_MA0[31:0];
    localparam [31:0] RST_MB0 = G300_MB0[31:0];
    localparam [31:0] RST_MA2 = G300_MA2[31:0];
    localparam [31:0] RST_MB2 = G300_MB2[31:0];
    localparam [31:0] RST_MW4 = G300_MW4[31:0];
    localparam [31:0] RST_MB4 = G300_MB4[31:0];

    reg [2:0] ctrl;
    assign soft_rst       = ctrl[0];
    assign pe_col_gate_en = ctrl[1];
    assign quad_en        = ctrl[2];

    wire [1:0] bsel = addr[1:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl <= CTRL_RST;
            ma0  <= RST_MA0;
            mb0  <= RST_MB0;
            ma2  <= RST_MA2;
            mb2  <= RST_MB2;
            mw4  <= RST_MW4;
            mb4  <= RST_MB4;
        end else if (we) begin
            if (addr == 8'h01) ctrl <= wdata[2:0];
            case (addr[7:2])
                6'h04: ma0[bsel*8 +: 8] <= wdata;
                6'h05: mb0[bsel*8 +: 8] <= wdata;
                6'h06: ma2[bsel*8 +: 8] <= wdata;
                6'h07: mb2[bsel*8 +: 8] <= wdata;
                6'h08: mw4[bsel*8 +: 8] <= wdata;
                6'h09: mb4[bsel*8 +: 8] <= wdata;
                default: ;
            endcase
        end
    end

    wire [23:0] bc24 = st_byte_cnt;            // zero-extended
    reg [31:0] mword;
    always @* begin
        case (addr[7:2])
            6'h04:   mword = ma0;
            6'h05:   mword = mb0;
            6'h06:   mword = ma2;
            6'h07:   mword = mb2;
            6'h08:   mword = mw4;
            6'h09:   mword = mb4;
            default: mword = 32'd0;
        endcase
        case (addr)
            8'h00:   rdata = ID_VAL;
            8'h01:   rdata = {5'd0, ctrl};
            8'h02:   rdata = {1'b0, st_layer, st_err_ovf, st_err_cmd, st_hrdy, st_done, st_busy};
            8'h03:   rdata = bc24[7:0];
            8'h04:   rdata = bc24[15:8];
            8'h05:   rdata = bc24[23:16];
            8'h06:   rdata = st_tile;
            default: rdata = (addr >= 8'h10 && addr <= 8'h27) ? mword[bsel*8 +: 8] : 8'h00;
        endcase
    end

endmodule
