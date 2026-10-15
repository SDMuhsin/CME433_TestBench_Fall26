`timescale 1ns / 1ps

// ============================================================================
// mq_bmem -- activation memory: 512 bytes in 2 macros (spec section 6).
// GEN_B[0] holds the even bytes, GEN_B[1] the odd bytes, row = addr[8:1].
//   w16 = 0  byte access: the addressed macro only, data in rdata[7:0]
//   w16 = 1  16-bit access at an even address: both macros, LE {odd, even}
// rdata is valid the cycle after an enabled read (selects registered).
// ============================================================================
module mq_bmem (
    input  wire        clk,
    input  wire        en,
    input  wire        we,
    input  wire        w16,
    input  wire [8:0]  addr,
    input  wire [15:0] wdata,
    output wire [15:0] rdata
);
    reg        odd_r, w16_r;
    wire [7:0] q0, q1;

    always @(posedge clk) begin
        if (en) begin odd_r <= addr[0]; w16_r <= w16; end
    end

    mq_sram_256x8 u_even (.clk(clk), .ce(en && (w16 || !addr[0])), .we(we), .addr(addr[8:1]),
                          .wdata(wdata[7:0]), .rdata(q0));
    mq_sram_256x8 u_odd  (.clk(clk), .ce(en && (w16 || addr[0])), .we(we), .addr(addr[8:1]),
                          .wdata(w16 ? wdata[15:8] : wdata[7:0]), .rdata(q1));

    assign rdata = w16_r ? {q1, q0} : {8'h00, odd_r ? q1 : q0};
endmodule
