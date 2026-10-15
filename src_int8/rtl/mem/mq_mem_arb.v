`timescale 1ns / 1ps

// ============================================================================
// mq_mem_arb -- single memory port shared by the sequencer and the host.
// The sequencer owns the port while it runs (seq_own); otherwise the host
// reads bytes of its 13-bit view (spec section 6):
//   h_addr[12] = 0  HMEM entry h_addr[11:2] as a 4-byte LE slot, byte
//                   h_addr[1:0] (byte 3 reads 0x00)  -> host 0x0000..0x0BFF
//   h_addr[12] = 1  BMEM byte h_addr[8:0]            -> host 0x1000..0x11FF
//                   (logits at 0x1040, 128 x INT16 LE)
// Host data is valid the cycle after h_req (mq_host_qspi read timing).
// ============================================================================
module mq_mem_arb (
    input  wire        clk,
    input  wire        seq_own,
    input  wire        s_en,
    input  wire        s_we,
    input  wire [11:0] s_addr,
    input  wire [1:0]  s_mw,
    input  wire        h_req,
    input  wire [12:0] h_addr,
    output reg  [7:0]  h_rdata,
    output wire        m_en,
    output wire        m_we,
    output wire [11:0] m_addr,
    output wire [1:0]  m_mw,
    input  wire [23:0] m_rdata
);
    reg       h_b;
    reg [1:0] h_byte;
    always @(posedge clk) begin
        if (h_req) begin h_b <= h_addr[12]; h_byte <= h_addr[1:0]; end
    end

    assign m_en   = seq_own ? s_en : h_req;
    assign m_we   = seq_own && s_we;
    assign m_addr = seq_own ? s_addr : h_addr[12] ? {3'b010, h_addr[8:0]} : {2'b00, h_addr[11:2]};
    assign m_mw   = seq_own ? s_mw : h_addr[12] ? 2'd0 : 2'd2;

    always @* begin
        if (h_b) h_rdata = m_rdata[7:0];
        else case (h_byte)
            2'd0:    h_rdata = m_rdata[7:0];
            2'd1:    h_rdata = m_rdata[15:8];
            2'd2:    h_rdata = m_rdata[23:16];
            default: h_rdata = 8'h00;
        endcase
    end
endmodule
