`timescale 1ns / 1ps

// ============================================================================
// mq_mem -- the 11-macro on-chip memory behind one port (spec section 6):
//   addr[11:10] = 0  HMEM, 768 x 24 b  (internal 0x000..0x2FF), width 24
//   addr[11:10] = 1  BMEM, 512 x 8 b   (internal 0x400..0x5FF), width 8 / 16
//   mw: 0 = 8 b, 1 = 16 b (even BMEM address), 2 = 24 b (HMEM).  rdata holds
// the value zero-padded above the access width, valid one clock after an
// enabled cycle.  Other address ranges read 0 and ignore writes.
// ============================================================================
module mq_mem (
    input  wire        clk,
    input  wire        en,
    input  wire        we,
    input  wire [11:0] addr,
    input  wire [1:0]  mw,
    input  wire [23:0] wdata,
    output wire [23:0] rdata
);
    wire hsel = (addr[11:10] == 2'b00);
    wire bsel = (addr[11:10] == 2'b01);
    reg  hsel_r;

    always @(posedge clk) begin
        if (en) hsel_r <= hsel;
    end

    wire [23:0] hq;
    wire [15:0] bq;
    mq_hmem u_h (.clk(clk), .en(en && hsel), .we(we), .addr(addr[9:0]), .wdata(wdata), .rdata(hq));
    mq_bmem u_b (.clk(clk), .en(en && bsel), .we(we), .w16(mw == 2'd1), .addr(addr[8:0]),
                 .wdata(wdata[15:0]), .rdata(bq));

    assign rdata = hsel_r ? hq : {8'h00, bq};
endmodule
