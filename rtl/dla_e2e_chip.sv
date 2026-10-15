`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// dla_e2e_chip -- END-TO-END G300 GAN generator ASIC (Chipathon 2026 A56 ACV).
//
// Same 11 user pins / pad terminals as dla_engine_chip (so A56_ACV.def and the
// FP template are reusable) and the same u_dla hierarchy (so the 8 SRAM macro
// instance names u_dla.u_a_buffer/u_b_buffer...u_sram are unchanged), but the
// chip now runs the whole 64->256->256->784 generator itself:
//
//   e2e_host_qspi : quad serial host interface (cmd byte 1-bit on IO0, quad
//                   weight stream, quad pixel readback, CSR + raw DLA debug)
//   e2e_csr       : ID/CTRL/STATUS + six writable requant multipliers (reset =
//                   golden G300 constants)
//   e2e_seq       : layer/tile sequencer, skid FIFO, bias double buffer,
//                   e2e_requant (shift-add requant + ReLU/sat + tanh ROM),
//                   activation ping-pong in B, 16-byte pixel tail stash
//   u_dla         : dla_engine_top with E2E_EXT=1 (runtime k_last, B read port)
//
// Pin roles (see docs/dla_e2e_chip.md):
//   W15 SCLK  in       W17 CS_N in
//   W16 MOSI = IO0  W18 MISO = IO1  W19 busy = IO2  W20 done = IO3  (bidir:
//                   OE driven by the interface, IE always on)
//   W21 wb_done = HRDY out (host ready / image done)
// ============================================================================
module dla_e2e_chip (
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

    // ---------------------------------------------------------------- host
    wire [15:0] h_addr;
    wire        csr_we;
    wire [7:0]  csr_wdata, csr_rdata;
    wire [1:0]  rd_src;
    wire        rd_req;
    reg  [7:0]  rd_data;
    wire        seq_start_cmd;
    wire [7:0]  st_byte;
    wire        st_valid;
    wire        dbg_wr_en, dbg_wr_sel, dbg_start;
    wire [7:0]  dbg_wr_data, dbg_k_last;
    wire        err_cmd_p;
    wire        quad_en, soft_rst, pe_col_gate_en;

    e2e_host_qspi u_host (
        .clk         (clk),
        .rst_n       (rst_n),
        .sclk_pad    (SCLK_IN),
        .cs_n_pad    (CS_N_IN),
        .io_in       (io_in),
        .io_out      (io_out),
        .io_oe       (io_oe),
        .quad_en     (quad_en),
        .h_addr      (h_addr),
        .csr_we      (csr_we),
        .csr_wdata   (csr_wdata),
        .rd_src      (rd_src),
        .rd_req      (rd_req),
        .rd_data     (rd_data),
        .seq_start   (seq_start_cmd),
        .st_byte     (st_byte),
        .st_valid    (st_valid),
        .dbg_wr_en   (dbg_wr_en),
        .dbg_wr_sel  (dbg_wr_sel),
        .dbg_wr_data (dbg_wr_data),
        .dbg_start   (dbg_start),
        .dbg_k_last  (dbg_k_last),
        .err_cmd     (err_cmd_p)
    );

    // ---------------------------------------------------------------- CSR
    wire [31:0] ma0, mb0, ma2, mb2, mw4, mb4;
    wire        s_armed, s_done, s_err_cmd, s_err_ovf;
    wire [1:0]  s_layer;
    wire [7:0]  s_tile;
    wire [18:0] s_byte_cnt;

    e2e_csr u_csr (
        .clk            (clk),
        .rst_n          (rst_n),
        .we             (csr_we),
        .addr           (h_addr[7:0]),
        .wdata          (csr_wdata),
        .rdata          (csr_rdata),
        .st_busy        (s_armed),
        .st_done        (s_done),
        .st_hrdy        (hrdy),
        .st_err_cmd     (s_err_cmd),
        .st_err_ovf     (s_err_ovf),
        .st_layer       (s_layer),
        .st_byte_cnt    (s_byte_cnt),
        .st_tile        (s_tile),
        .soft_rst       (soft_rst),
        .pe_col_gate_en (pe_col_gate_en),
        .quad_en        (quad_en),
        .ma0 (ma0), .mb0 (mb0), .ma2 (ma2), .mb2 (mb2), .mw4 (mw4), .mb4 (mb4)
    );

    // ---------------------------------------------------------------- sequencer
    wire        dla_start, dla_wr_en, dla_wr_sel, dla_rd_en;
    wire [7:0]  dla_k_last;
    wire [9:0]  dla_wr_addr;
    wire [7:0]  dla_wr_data;
    wire [3:0]  dla_rd_addr;
    wire signed [23:0] dla_rd_data;
    wire        dla_wb_done, dla_done, dla_busy;
    wire        dla_active;
    wire [31:0] b_rd_data;
    wire [7:0]  stash_rd_data;

    e2e_seq u_seq (
        .clk           (clk),
        .rst_n         (rst_n),
        .soft_rst      (soft_rst),
        .start_cmd     (seq_start_cmd),
        .st_byte       (st_byte),
        .st_valid      (st_valid),
        .err_cmd_in    (err_cmd_p),
        .ma0 (ma0), .mb0 (mb0), .ma2 (ma2), .mb2 (mb2), .mw4 (mw4), .mb4 (mb4),
        .dbg_wr_en     (dbg_wr_en),
        .dbg_wr_sel    (dbg_wr_sel),
        .dbg_wr_addr   (h_addr[9:0]),
        .dbg_wr_data   (dbg_wr_data),
        .dbg_start     (dbg_start),
        .dbg_k_last    (dbg_k_last),
        .dbg_rd_en     (rd_src == 2'd3),
        .dbg_rd_addr   (h_addr[5:2]),
        .dla_start     (dla_start),
        .dla_k_last    (dla_k_last),
        .dla_wr_en     (dla_wr_en),
        .dla_wr_sel    (dla_wr_sel),
        .dla_wr_addr   (dla_wr_addr),
        .dla_wr_data   (dla_wr_data),
        .dla_rd_en     (dla_rd_en),
        .dla_rd_addr   (dla_rd_addr),
        .dla_rd_data   (dla_rd_data),
        .dla_wb_done   (dla_wb_done),
        .dla_active    (dla_active),
        .stash_rd_addr (h_addr[3:0]),
        .stash_rd_data (stash_rd_data),
        .armed         (s_armed),
        .done          (s_done),
        .hrdy          (hrdy),
        .err_cmd       (s_err_cmd),
        .err_ovf       (s_err_ovf),
        .layer         (s_layer),
        .tile          (s_tile),
        .byte_cnt      (s_byte_cnt)
    );

    // ---------------------------------------------------------------- DLA core
    // Pixel readback reads one B row (all 4 columns) while the DLA is idle.
    wire b_rd_sel = (rd_src == 2'd2) && !dla_active;

    dla_engine_top #(
        .E2E_EXT (1)
    ) u_dla (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (dla_start),
        .wr_en     (dla_wr_en),
        .wr_sel    (dla_wr_sel),
        .wr_addr   (dla_wr_addr),
        .wr_data   (dla_wr_data),
        .rd_en     (dla_rd_en),
        .rd_addr   (dla_rd_addr),
        .rd_data   (dla_rd_data),
        .k_last    (dla_k_last),
        .b_rd_sel  (b_rd_sel),
        .b_rd_addr (h_addr[7:0]),
        .b_rd_data (b_rd_data),
        .wb_done   (dla_wb_done),
        .done      (dla_done),
        .busy      (dla_busy)
    );

    // ---------------------------------------------------------------- read mux
    // pixel p: p < 768 -> B col (1 + p/256) row p%256 ; p >= 768 -> tail stash.
    // h_addr is stable from rd_req through the capture cycle.
    reg [7:0] pix_b;
    always @* begin
        case (h_addr[9:8])
            2'd0:    pix_b = b_rd_data[15:8];
            2'd1:    pix_b = b_rd_data[23:16];
            default: pix_b = b_rd_data[31:24];
        endcase
    end
    wire       pix_tail = (h_addr[9:8] == 2'd3);
    wire [7:0] pix_data = pix_tail ? stash_rd_data : pix_b;

    reg [7:0] c_byte;
    always @* begin
        case (h_addr[1:0])
            2'd0:    c_byte = dla_rd_data[7:0];
            2'd1:    c_byte = dla_rd_data[15:8];
            2'd2:    c_byte = dla_rd_data[23:16];
            default: c_byte = {8{dla_rd_data[23]}};
        endcase
    end

    always @* begin
        case (rd_src)
            2'd1:    rd_data = csr_rdata;
            2'd2:    rd_data = pix_data;
            2'd3:    rd_data = c_byte;
            default: rd_data = 8'h00;
        endcase
    end

    // ---- unused ----
    wire _unused;
    assign _unused = &{1'b0, wb_done_IN, dla_done, dla_busy, pe_col_gate_en, h_addr[15:10],
                        rd_req, b_rd_data[7:0]};

endmodule

`default_nettype wire
