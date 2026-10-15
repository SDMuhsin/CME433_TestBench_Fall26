`timescale 1ns / 1ps

// ============================================================================
// fp16_csr -- byte-addressed control/status registers of dla_fp16_chip.
//
//   0x00       ID = 0xF6 (RO)
//   0x01       CTRL: [0] soft_reset_seq, [1] reserved (rw, no effect),
//              [2] quad_en (STREAM_Q nibble mode; reset 1)
//   0x02       STATUS (RO): [0] busy (image in flight), [1] done, [2] hrdy,
//              [3] err_cmd, [4] err_overflow, [6:5] layer
//   0x03-0x05  stream byte count (RO, 20 b, little endian)
//   0x06-0x07  current neuron index (RO, 10 b, little endian)
// Unmapped addresses (incl. the INT8 requant range 0x10-0x27) read 0x00;
// writes to RO/unmapped addresses are ignored.  No arithmetic constants:
// FP16 needs no requant multipliers.
// ============================================================================
module fp16_csr (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,
    input  wire [7:0]  addr,
    input  wire [7:0]  wdata,
    output reg  [7:0]  rdata,

    input  wire        st_busy,
    input  wire        st_done,
    input  wire        st_hrdy,
    input  wire        st_err_cmd,
    input  wire        st_err_ovf,
    input  wire [1:0]  st_layer,
    input  wire [19:0] st_byte_cnt,
    input  wire [9:0]  st_neuron,

    output wire        soft_rst,
    output wire        quad_en
);
    localparam [7:0] ID_VAL   = 8'hF6;
    localparam [2:0] CTRL_RST = 3'b100;

    reg [2:0] ctrl;
    assign soft_rst = ctrl[0];
    assign quad_en  = ctrl[2];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                      ctrl <= CTRL_RST;
        else if (we && addr == 8'h01)    ctrl <= wdata[2:0];
    end

    always @* begin
        case (addr)
            8'h00:   rdata = ID_VAL;
            8'h01:   rdata = {5'd0, ctrl};
            8'h02:   rdata = {1'b0, st_layer, st_err_ovf, st_err_cmd, st_hrdy, st_done, st_busy};
            8'h03:   rdata = st_byte_cnt[7:0];
            8'h04:   rdata = st_byte_cnt[15:8];
            8'h05:   rdata = {4'd0, st_byte_cnt[19:16]};
            8'h06:   rdata = st_neuron[7:0];
            8'h07:   rdata = {6'd0, st_neuron[9:8]};
            default: rdata = 8'h00;
        endcase
    end
endmodule
