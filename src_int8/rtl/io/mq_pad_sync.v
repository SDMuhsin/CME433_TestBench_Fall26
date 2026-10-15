`timescale 1ns / 1ps

// ============================================================================
// mq_pad_sync -- host pad synchronisers (copied from the FP16 chip): SCLK,
// CS_N and IO[3:0] are asynchronous pad inputs, double-flopped into clk;
// SCLK rising edges are detected in the clk domain (no second clock domain).
// ============================================================================
module mq_pad_sync (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sclk_pad,
    input  wire       cs_n_pad,
    input  wire [3:0] io_pad,
    output wire       rise,
    output wire       cs_n,
    output reg  [3:0] io
);
    reg [1:0] sclk_s, cs_n_s;
    reg [3:0] io_s1;
    reg       sclk_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sclk_s <= 2'b00; cs_n_s <= 2'b11; io_s1 <= 4'h0; io <= 4'h0; sclk_prev <= 1'b0;
        end else begin
            sclk_s    <= {sclk_s[0], sclk_pad};
            cs_n_s    <= {cs_n_s[0], cs_n_pad};
            io_s1     <= io_pad;
            io        <= io_s1;
            sclk_prev <= sclk_s[1];
        end
    end

    assign rise = sclk_s[1] & ~sclk_prev;
    assign cs_n = cs_n_s[1];
endmodule
