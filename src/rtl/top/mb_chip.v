`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// mb_chip -- Mamba selective-SSM byte-LM ASIC (spec: src/docs/spec.md,
// architecture: src/docs/arch.md).
//
// Same 11 user pins / pad terminals as dla_fp16_chip (die, pad ring and pin
// template are reused): W13 clk, W14 rst_n, W15 SCLK in, W17 CS_N in,
// W16/W18/W19/W20 = quad IO0..IO3 (bidir), W21 = HRDY out.
//
//   mb_host_qspi : quad serial host link (WR/RD_CSR, START, STREAM_Q, RD_MEM[_Q])
//   mb_csr       : ID 0x4D / CTRL (soft reset, STATE_RESET, quad) / STATUS
//   mb_core      : stream FIFO, microcoded sequencer, MAC lane, NLU, 10 SRAMs
//
// Per token the host sends START, streams the 99,840-byte weight stream
// (honouring HRDY), waits for HRDY, then reads the 128 FP16 logits as memory
// bytes 0x800..0x8FF (RD_MEM_Q, MSB byte first).  A new story starts with a
// CTRL.STATE_RESET write (also required once after power-up).
// ============================================================================
module mb_chip (
    // --- W13 clk (in_s) ---
    input  wire clk,
    output wire clk_PU,
    output wire clk_PD,
    // --- W14 rst_n (in_c) ---
    input  wire rst_n,
    output wire rst_n_PU,
    output wire rst_n_PD,

    // --- W15 SCLK (bi_24t, host -> chip) ---
    input  wire SCLK_IN,
    output wire SCLK_OUT,
    output wire SCLK_OE,
    output wire SCLK_IE,
    output wire SCLK_CS,
    output wire SCLK_SL,
    output wire SCLK_PU,
    output wire SCLK_PD,
    // --- W16 MOSI = IO0 (bi_24t, bidirectional) ---
    input  wire MOSI_IN,
    output wire MOSI_OUT,
    output wire MOSI_OE,
    output wire MOSI_IE,
    output wire MOSI_CS,
    output wire MOSI_SL,
    output wire MOSI_PU,
    output wire MOSI_PD,
    // --- W17 CS_N (bi_24t, host -> chip) ---
    input  wire CS_N_IN,
    output wire CS_N_OUT,
    output wire CS_N_OE,
    output wire CS_N_IE,
    output wire CS_N_CS,
    output wire CS_N_SL,
    output wire CS_N_PU,
    output wire CS_N_PD,
    // --- W18 MISO = IO1 (bi_24t, bidirectional) ---
    input  wire MISO_IN,
    output wire MISO_OUT,
    output wire MISO_OE,
    output wire MISO_IE,
    output wire MISO_CS,
    output wire MISO_SL,
    output wire MISO_PU,
    output wire MISO_PD,
    // --- W19 busy = IO2 (bi_24t, bidirectional) ---
    input  wire busy_IN,
    output wire busy_OUT,
    output wire busy_OE,
    output wire busy_IE,
    output wire busy_CS,
    output wire busy_SL,
    output wire busy_PU,
    output wire busy_PD,
    // --- W20 done = IO3 (bi_24t, bidirectional) ---
    input  wire done_IN,
    output wire done_OUT,
    output wire done_OE,
    output wire done_IE,
    output wire done_CS,
    output wire done_SL,
    output wire done_PU,
    output wire done_PD,
    // --- W21 wb_done = HRDY (bi_24t, chip -> host) ---
    input  wire wb_done_IN,
    output wire wb_done_OUT,
    output wire wb_done_OE,
    output wire wb_done_IE,
    output wire wb_done_CS,
    output wire wb_done_SL,
    output wire wb_done_PU,
    output wire wb_done_PD
);

    // ---- dedicated input pads: no pulls ----
    assign clk_PU   = 1'b0;  assign clk_PD   = 1'b0;
    assign rst_n_PU = 1'b0;  assign rst_n_PD = 1'b0;

    // ---- host -> chip input pads (SCLK, CS_N): driver off, receiver on ----
    assign SCLK_OUT = 1'b0; assign SCLK_OE = 1'b0; assign SCLK_IE = 1'b1;
    assign SCLK_CS  = 1'b0; assign SCLK_SL = 1'b0; assign SCLK_PU = 1'b0; assign SCLK_PD = 1'b0;
    assign CS_N_OUT = 1'b0; assign CS_N_OE = 1'b0; assign CS_N_IE = 1'b1;
    assign CS_N_CS  = 1'b0; assign CS_N_SL = 1'b0; assign CS_N_PU = 1'b0; assign CS_N_PD = 1'b0;

    // ---- quad IO[3:0] = MOSI, MISO, busy, done pads ----
    wire [3:0] io_in = {done_IN, busy_IN, MISO_IN, MOSI_IN};
    wire [3:0] io_out, io_oe;

    assign MOSI_OUT = io_out[0]; assign MOSI_OE = io_oe[0]; assign MOSI_IE = 1'b1;
    assign MOSI_CS  = 1'b0; assign MOSI_SL = 1'b0; assign MOSI_PU = 1'b0; assign MOSI_PD = 1'b0;
    assign MISO_OUT = io_out[1]; assign MISO_OE = io_oe[1]; assign MISO_IE = 1'b1;
    assign MISO_CS  = 1'b0; assign MISO_SL = 1'b0; assign MISO_PU = 1'b0; assign MISO_PD = 1'b0;
    assign busy_OUT = io_out[2]; assign busy_OE = io_oe[2]; assign busy_IE = 1'b1;
    assign busy_CS  = 1'b0; assign busy_SL = 1'b0; assign busy_PU = 1'b0; assign busy_PD = 1'b0;
    assign done_OUT = io_out[3]; assign done_OE = io_oe[3]; assign done_IE = 1'b1;
    assign done_CS  = 1'b0; assign done_SL = 1'b0; assign done_PU = 1'b0; assign done_PD = 1'b0;

    // ---- HRDY on the W21 (ex wb_done) output pad ----
    wire hrdy;
    assign wb_done_OUT = hrdy; assign wb_done_OE = 1'b1; assign wb_done_IE = 1'b0;
    assign wb_done_CS  = 1'b0; assign wb_done_SL = 1'b0; assign wb_done_PU = 1'b0; assign wb_done_PD = 1'b0;

    // ---------------------------------------------------------------- host link
    wire [15:0] h_addr;
    wire        csr_we, rd_mem, rd_req, start, st_valid, err_cmd_p, quad_en;
    wire [7:0]  csr_wdata, csr_rdata, mem_rdata, st_byte;

    mb_host_qspi u_host (
        .clk(clk), .rst_n(rst_n), .sclk_pad(SCLK_IN), .cs_n_pad(CS_N_IN),
        .io_in(io_in), .io_out(io_out), .io_oe(io_oe), .quad_en(quad_en),
        .h_addr(h_addr), .csr_we(csr_we), .csr_wdata(csr_wdata),
        .rd_mem(rd_mem), .rd_req(rd_req), .rd_data(rd_mem ? mem_rdata : csr_rdata),
        .seq_start(start), .st_byte(st_byte), .st_valid(st_valid), .err_cmd(err_cmd_p));

    // ---------------------------------------------------------------- CSR
    wire        soft_rst, clr_state, busy, done, tok, err_ovf;
    wire [19:0] byte_cnt;
    wire [7:0]  upc;

    mb_csr u_csr (
        .clk(clk), .rst_n(rst_n), .we(csr_we), .addr(h_addr[7:0]), .wdata(csr_wdata),
        .rdata(csr_rdata), .start(start), .err_cmd_p(err_cmd_p),
        .st_busy(busy), .st_done(done), .st_hrdy(hrdy), .st_err_ovf(err_ovf), .st_tok(tok),
        .st_byte_cnt(byte_cnt), .st_upc(upc),
        .soft_rst(soft_rst), .clr_state(clr_state), .quad_en(quad_en));

    // ---------------------------------------------------------------- core
    mb_core u_core (
        .clk(clk), .rst_n(rst_n), .start(start), .clr_state(clr_state), .abort(soft_rst),
        .st_byte(st_byte), .st_valid(st_valid),
        .h_req(rd_req && rd_mem), .h_addr(h_addr[11:0]), .h_rdata(mem_rdata),
        .hrdy(hrdy), .busy(busy), .done(done), .tok(tok), .err_ovf(err_ovf),
        .byte_cnt(byte_cnt), .upc(upc));

    wire _unused = &{1'b0, wb_done_IN, h_addr[15:12]};
endmodule

`default_nettype wire
