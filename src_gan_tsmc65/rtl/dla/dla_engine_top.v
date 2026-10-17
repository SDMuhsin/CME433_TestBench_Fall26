`timescale 1ns / 1ps

// Top-level DLA engine:
// - Loads A and B matrix elements through a shared write port.
// - Runs controller-driven PE accumulation across K cycles.
// - Exposes C matrix elements through a read address/data interface.
module dla_engine_top #(
    parameter N         = 4,
    // K=256 matches the deepest contraction in the G300 GAN (layers 2 and 4 both take a
    // 256-wide input) so a single `start` computes a full dot product natively -- no
    // external K-tiling/accumulation needed. The A/B SRAM macros are already 256-deep
    // (dla_a/b_buffer_bank hardcode SRAM_ADDR_W=8), so this uses existing macro capacity,
    // not new ones. 2026-07-02: was K=4 through the first 3.3V signoff (as3v3_d61); that
    // build could not run the real GAN workload in one `start` (see README.md).
    parameter K         = 256,
    parameter DATA_W    = 8,
    parameter ACC_W     = 24,
    parameter AB_ADDR_W = (N*K <= 1) ? 1 : $clog2(N*K),
    parameter C_ADDR_W  = (N*N <= 1) ? 1 : $clog2(N*N),
    parameter K_IDX_W   = (K <= 1) ? 1 : $clog2(K),
    parameter SRAM_LATENCY = 1,
    // E2E_EXT=1 enables the two dla_e2e_chip extensions (default 0 = the
    // signed-off core, bit-identical behaviour; the extra ports may be left
    // unconnected):
    //   * k_last  : runtime contraction length (COMPUTE ends at k_idx == k_last)
    //   * b_rd_*  : external read of one B row (all N columns, 1-clk latency)
    //               while the controller is idle; b_rd_sel muxes the B bank's
    //               read row from k_idx to b_rd_addr.
    parameter E2E_EXT = 0
) (
    input                            clk,
    input                            rst_n,
    input                            start,

    input                            wr_en,
    input                            wr_sel,
    input [AB_ADDR_W-1:0]            wr_addr,
    input signed [DATA_W-1:0]        wr_data,

    input                            rd_en,
    input [C_ADDR_W-1:0]             rd_addr,
    output signed [ACC_W-1:0]        rd_data,

    input  [K_IDX_W-1:0]             k_last,
    input                            b_rd_sel,
    input  [K_IDX_W-1:0]             b_rd_addr,
    output [(N*DATA_W)-1:0]          b_rd_data,

    output reg                       wb_done,
    output                           done,
    output                           busy
);

    wire clear_pe;
    wire en_pe;
    wire done_raw;
    wire busy_raw;
    wire [K_IDX_W-1:0] k_idx;
    reg en_pe_d;
    reg done_d;
    reg busy_d;

    wire signed [(N*DATA_W)-1:0] a_row_vector;
    wire signed [(N*DATA_W)-1:0] b_col_vector;
    wire signed [(N*N*ACC_W)-1:0] c_bus;
    wire signed [ACC_W-1:0] c_sram_rd_data;

    localparam integer C_DEPTH = N * N;
    localparam [C_ADDR_W-1:0] C_LAST = (C_DEPTH <= 1)
        ? {C_ADDR_W{1'b0}}
        : (C_DEPTH - 1);

    reg wb_active;
    reg [C_ADDR_W-1:0] wb_idx;
    wire c_wr_ack;              // C bank pulses this on the last byte plane of a word
    reg done_use_q;

    dla_controller #(
        .K(K),
        .K_IDX_W(K_IDX_W),
        .EXT_K_LAST(E2E_EXT)
    ) u_controller (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .k_last(E2E_EXT ? k_last : {K_IDX_W{1'b1}}),
        .clear_pe(clear_pe),
        .en_pe(en_pe),
        .k_idx(k_idx),
        .done(done_raw),
        .busy(busy_raw)
    );

    // One-cycle pipeline to align SRAM-registered data with PE enable and status.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en_pe_d <= 1'b0;
            done_d  <= 1'b0;
            busy_d  <= 1'b0;
        end else begin
            en_pe_d <= en_pe;
            done_d  <= done_raw;
            busy_d  <= busy_raw;
        end
    end

    wire en_pe_use  = SRAM_LATENCY ? en_pe_d  : en_pe;
    wire done_use   = SRAM_LATENCY ? done_d   : done_raw;
    wire busy_use   = SRAM_LATENCY ? busy_d   : busy_raw;

    wire start_wb = done_use && !done_use_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wb_active <= 1'b0;
            wb_idx    <= {C_ADDR_W{1'b0}};
            wb_done   <= 1'b0;
            done_use_q <= 1'b0;
        end else begin
            done_use_q <= done_use;

            if (start) begin
                wb_done <= 1'b0;
            end

            if (start_wb) begin
                wb_active <= 1'b1;
                wb_idx    <= {C_ADDR_W{1'b0}};
            end else if (wb_active && c_wr_ack) begin
                // c_wr_ack pulses on the last byte plane of the current word, so
                // each accumulator occupies 3 cycles here rather than 1 -- the C
                // bank now folds 24 bits into one 8-bit macro.  See
                // dla_c_buffer_bank.v.  Writeback is 48 cycles, not 16.
                if (wb_idx == C_LAST) begin
                    wb_active <= 1'b0;
                    wb_done   <= 1'b1;
                end else begin
                    wb_idx <= wb_idx + 1'b1;
                end
            end
        end
    end

    wire c_wr_en = wb_active;
    wire [C_ADDR_W-1:0] c_wr_addr = wb_idx;
    wire signed [ACC_W-1:0] c_wr_data = c_bus[(wb_idx*ACC_W) +: ACC_W];

    dla_a_buffer_bank #(
        .N(N),
        .K(K),
        .DATA_W(DATA_W),
        .ADDR_W(AB_ADDR_W),
        .K_IDX_W(K_IDX_W),
        .USE_SRAM(1)   // A buffer = 4 x dla_sram_1rw_256x8 (65 nm: latch RF)
    ) u_a_buffer (
        .clk(clk),
        .wr_en(wr_en && !wr_sel),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_col(k_idx),
        .row_vector(a_row_vector)
    );

    // E2E_EXT: host/sequencer read of B (only meaningful while idle; k_idx is 0
    // then).  With E2E_EXT=0 this folds back to the original rd_row = k_idx.
    wire [K_IDX_W-1:0] b_rd_row = (E2E_EXT && b_rd_sel) ? b_rd_addr : k_idx;
    assign b_rd_data = E2E_EXT ? b_col_vector : {(N*DATA_W){1'b0}};

    dla_b_buffer_bank #(
        .N(N),
        .K(K),
        .DATA_W(DATA_W),
        .ADDR_W(AB_ADDR_W),
        .K_IDX_W(K_IDX_W),
        .USE_SRAM(1)   // B buffer = 4 x dla_sram_1rw_256x8 (65 nm: latch RF)
    ) u_b_buffer (
        .clk(clk),
        .wr_en(wr_en && wr_sel),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_row(b_rd_row),
        .col_vector(b_col_vector)
    );

    dla_pe_array #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) u_pe_array (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear_pe),
        .en(en_pe_use),
        .a_bus(a_row_vector),
        .b_bus(b_col_vector),
        .c_bus(c_bus)
    );

    // Store the completed C matrix for host/testbench reads: N*N x 24-bit
    // flip-flops with a 1-cycle registered read (dla_c_buffer_bank.v).
    dla_c_buffer_bank #(
        .N(N),
        .ACC_W(ACC_W),
        .ADDR_W(C_ADDR_W),
        .USE_SRAM(0)
    ) u_c_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .wr_en(c_wr_en),
        .wr_addr(c_wr_addr),
        .wr_data(c_wr_data),
        .wr_ack(c_wr_ack),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rd_data(c_sram_rd_data)
    );

    assign rd_data = c_sram_rd_data;

    assign done = done_use;
    assign busy = busy_use || wb_active;

endmodule
