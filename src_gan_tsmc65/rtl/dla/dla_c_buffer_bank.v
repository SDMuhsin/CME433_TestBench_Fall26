`timescale 1ns / 1ps

// ============================================================================
// dla_c_buffer_bank -- C buffer: N*N accumulated ACC_W-bit outputs in
// flip-flops with a 1-cycle registered read.
//
// 65 nm copy of rtl/dla_c_buffer_bank.v reduced to its register branch
// (GEN_REG, the one the legacy chip instantiates with USE_SRAM(0)); the
// folded 64x8 SRAM-macro branch is removed.  Behaviour is identical: a write
// completes in the cycle it is issued (wr_ack = wr_en), a read returns the
// word one clock after rd_en.  USE_SRAM is kept as an ignored parameter so the
// dla_engine_top instantiation is unchanged.
// ============================================================================
module dla_c_buffer_bank #(
    parameter N        = 4,
    parameter ACC_W    = 24,
    parameter ADDR_W   = (N*N <= 1) ? 1 : $clog2(N*N),
    parameter USE_SRAM = 0
) (
    input                              clk,
    input                              rst_n,
    input                              wr_en,
    input [ADDR_W-1:0]                 wr_addr,
    input signed [ACC_W-1:0]           wr_data,
    output                             wr_ack,
    input                              rd_en,
    input [ADDR_W-1:0]                 rd_addr,
    output signed [ACC_W-1:0]          rd_data
);

    localparam integer C_DEPTH = N * N;

    reg signed [ACC_W-1:0] mem [0:C_DEPTH-1];
    reg signed [ACC_W-1:0] rd_reg;

    always @(posedge clk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
        if (rd_en) begin
            rd_reg <= mem[rd_addr];
        end
    end

    assign rd_data = rd_reg;
    assign wr_ack  = wr_en;

    wire _unused = &{1'b0, rst_n};

endmodule
