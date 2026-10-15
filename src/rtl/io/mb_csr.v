`timescale 1ns / 1ps

// ============================================================================
// mb_csr -- byte-addressed control/status registers of mb_chip.
//
//   0x00       ID = 0x4D ('M') (RO)
//   0x01       CTRL: [0] soft reset (rw; stops the sequencer while 1),
//              [1] STATE_RESET (write 1: zero the SSM / conv state; reads 0),
//              [2] quad_en (STREAM_Q nibble mode; reset 1)
//   0x02       STATUS (RO): [0] busy, [1] done, [2] hrdy, [3] err_cmd (sticky,
//              cleared by START / STATE_RESET), [4] err_overflow, [5] token step
//              in flight (else the state reset)
//   0x03-0x05  stream byte count of the current token (RO, 20 b, little endian)
//   0x06       microcode program counter (RO)
// Unmapped addresses read 0x00; writes to RO / unmapped addresses are ignored.
// ============================================================================
module mb_csr (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,
    input  wire [7:0]  addr,
    input  wire [7:0]  wdata,
    output reg  [7:0]  rdata,
    input  wire        start,
    input  wire        err_cmd_p,
    input  wire        st_busy,
    input  wire        st_done,
    input  wire        st_hrdy,
    input  wire        st_err_ovf,
    input  wire        st_tok,
    input  wire [19:0] st_byte_cnt,
    input  wire [7:0]  st_upc,
    output wire        soft_rst,
    output wire        clr_state,
    output wire        quad_en
);
    localparam [7:0] ID_VAL = 8'h4D;

    reg [1:0] ctrl;                  // {quad_en, soft_rst}
    reg       err_cmd;
    assign soft_rst  = ctrl[0];
    assign quad_en   = ctrl[1];
    assign clr_state = we && addr == 8'h01 && wdata[1];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ctrl    <= 2'b10;
            err_cmd <= 1'b0;
        end else begin
            if (we && addr == 8'h01) ctrl <= {wdata[2], wdata[0]};
            if (start || clr_state)  err_cmd <= 1'b0;
            else if (err_cmd_p)      err_cmd <= 1'b1;
        end
    end

    always @* begin
        case (addr)
            8'h00:   rdata = ID_VAL;
            8'h01:   rdata = {5'd0, ctrl[1], 1'b0, ctrl[0]};
            8'h02:   rdata = {2'd0, st_tok, st_err_ovf, err_cmd, st_hrdy, st_done, st_busy};
            8'h03:   rdata = st_byte_cnt[7:0];
            8'h04:   rdata = st_byte_cnt[15:8];
            8'h05:   rdata = {4'd0, st_byte_cnt[19:16]};
            8'h06:   rdata = st_upc;
            default: rdata = 8'h00;
        endcase
    end
endmodule
