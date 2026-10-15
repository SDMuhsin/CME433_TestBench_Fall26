`timescale 1ns / 1ps

// ============================================================================
// mb_mem_arb -- single memory port shared by the sequencer and the host.
// The sequencer owns the port while it runs (seq_own); otherwise the host
// reads bytes: h_addr[11:1] = word, h_addr[0] = byte (0 = high byte, the
// stream's MSB-first order), so the logits are host bytes 0x800..0x8FF.
// Host data is valid the cycle after h_req (mb_host_qspi read timing).
// ============================================================================
module mb_mem_arb (
    input  wire        clk,
    input  wire        seq_own,
    input  wire        s_en,
    input  wire        s_we,
    input  wire [10:0] s_addr,
    input  wire        h_req,
    input  wire [11:0] h_addr,
    output wire [7:0]  h_rdata,
    output wire        m_en,
    output wire        m_we,
    output wire [10:0] m_addr,
    input  wire [15:0] m_rdata
);
    reg h_lo;
    always @(posedge clk) begin
        if (h_req) h_lo <= h_addr[0];
    end

    assign m_en    = seq_own ? s_en : h_req;
    assign m_we    = seq_own && s_we;
    assign m_addr  = seq_own ? s_addr : h_addr[11:1];
    assign h_rdata = h_lo ? m_rdata[7:0] : m_rdata[15:8];
endmodule
