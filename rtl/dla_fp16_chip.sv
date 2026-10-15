`timescale 1ns / 1ps
`default_nettype none

// ============================================================================
// dla_fp16_chip -- END-TO-END G300 GAN generator ASIC, FP16 version
// (Chipathon 2026 A56 ACV block; spec: docs/).
//
// Same 11 user pins / pad terminals and host protocol as dla_e2e_chip (so
// A56_ACV.def and the FP template are reusable), same 8 GF180 OCD 256x8 SRAM
// macros at the same sites, but an IEEE-binary16 datapath:
//
//   e2e_host_qspi : quad serial host interface (reused unchanged); the raw
//                   INT8 DLA debug commands (0x10-0x13) are accepted but have
//                   no effect (DBG_RD_C reads 0x00)
//   fp16_csr      : ID 0xF6 / CTRL / STATUS / byte count / neuron
//   fp16_seq      : stream decoder + layer sequencer (weights consumed straight
//                   from the stream; no weight SRAM)
//   fp16_lane     : 1 FP16xFP16 -> exact FP32 product, FP32 RNE accumulate
//                   (3-stage pipeline, sequential fixed-order accumulation)
//   fp16_epi      : FP32 -> FP16 (FTZ / RNE / saturate), ReLU, tanh-pixel
//                   threshold search (fp16_tanh_rom)
//   SRAM          : GEN_ACT[0..3] = act pairs P0 {lo,hi} = [0],[1], P1 = [2],[3]
//                   (256 x 16 b each); GEN_PIX[0..3] = 1024 x 8 pixel buffer
//
// Pin roles (unchanged): W15 SCLK in, W17 CS_N in, W16/W18/W19/W20 = IO0..IO3
// bidir, W21 (ex wb_done) = HRDY out.
// Pixels are uint8 0..255 (RD_PIX_Q / RD_PIX, address 0..783).
// ============================================================================
module dla_fp16_chip (
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
    wire        quad_en, soft_rst;

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
    wire        s_armed, s_done, s_err_cmd, s_err_ovf;
    wire [1:0]  s_layer;
    wire [9:0]  s_neuron;
    wire [19:0] s_byte_cnt;

    fp16_csr u_csr (
        .clk         (clk),
        .rst_n       (rst_n),
        .we          (csr_we),
        .addr        (h_addr[7:0]),
        .wdata       (csr_wdata),
        .rdata       (csr_rdata),
        .st_busy     (s_armed),
        .st_done     (s_done),
        .st_hrdy     (hrdy),
        .st_err_cmd  (s_err_cmd),
        .st_err_ovf  (s_err_ovf),
        .st_layer    (s_layer),
        .st_byte_cnt (s_byte_cnt),
        .st_neuron   (s_neuron),
        .soft_rst    (soft_rst),
        .quad_en     (quad_en)
    );

    // ---------------------------------------------------------------- sequencer
    wire        lane_issue, lane_ld_bias, lane_can_issue, lane_idle, lane_clear;
    wire [15:0] lane_w, lane_x, lane_bias;
    wire [31:0] lane_acc;
    wire        epi_go, epi_tanh, epi_busy, epi_done;
    wire [15:0] epi_y;
    wire [7:0]  epi_pix;
    wire [7:0]  act_addr0, act_addr1;
    wire [1:0]  act_we;
    wire [15:0] act_wdata, act_rdata0, act_rdata1;
    wire        pix_we;
    wire [9:0]  pix_waddr;
    wire [7:0]  pix_wdata;

    fp16_seq u_seq (
        .clk            (clk),
        .rst_n          (rst_n),
        .soft_rst       (soft_rst),
        .start_cmd      (seq_start_cmd),
        .st_byte        (st_byte),
        .st_valid       (st_valid),
        .err_cmd_in     (err_cmd_p),
        .lane_issue     (lane_issue),
        .lane_w         (lane_w),
        .lane_x         (lane_x),
        .lane_ld_bias   (lane_ld_bias),
        .lane_bias      (lane_bias),
        .lane_can_issue (lane_can_issue),
        .lane_idle      (lane_idle),
        .lane_clear     (lane_clear),
        .epi_go         (epi_go),
        .epi_tanh       (epi_tanh),
        .epi_busy       (epi_busy),
        .epi_done       (epi_done),
        .epi_y          (epi_y),
        .epi_pix        (epi_pix),
        .act_addr0      (act_addr0),
        .act_addr1      (act_addr1),
        .act_we         (act_we),
        .act_wdata      (act_wdata),
        .act_rdata0     (act_rdata0),
        .act_rdata1     (act_rdata1),
        .pix_we         (pix_we),
        .pix_waddr      (pix_waddr),
        .pix_wdata      (pix_wdata),
        .armed          (s_armed),
        .done           (s_done),
        .hrdy           (hrdy),
        .err_cmd        (s_err_cmd),
        .err_ovf        (s_err_ovf),
        .layer          (s_layer),
        .neuron         (s_neuron),
        .byte_cnt       (s_byte_cnt)
    );

    // ---------------------------------------------------------------- MAC lane + epilogue
    fp16_lane u_lane (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (lane_clear),
        .issue     (lane_issue),
        .w         (lane_w),
        .x         (lane_x),
        .ld_bias   (lane_ld_bias),
        .bias      (lane_bias),
        .can_issue (lane_can_issue),
        .idle      (lane_idle),
        .acc       (lane_acc)
    );

    fp16_epi u_epi (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (lane_clear),
        .go        (epi_go),
        .tanh_mode (epi_tanh),
        .acc       (lane_acc),
        .y         (epi_y),
        .pix       (epi_pix),
        .busy      (epi_busy),
        .done      (epi_done)
    );

    // ---------------------------------------------------------------- SRAM macros
    // Activation pairs: GEN_ACT[2p + b] = pair p, byte b (b = 0 low byte).
    wire [7:0] act_q [0:3];
    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : GEN_ACT
            dla_sram_1rw_256x8 u_sram (
                .clk   (clk),
                .we    (act_we[gi / 2]),
                .addr  ((gi < 2) ? act_addr0 : act_addr1),
                .wdata ((gi % 2 == 1) ? act_wdata[15:8] : act_wdata[7:0]),
                .rdata (act_q[gi])
            );
        end
    endgenerate
    assign act_rdata0 = {act_q[1], act_q[0]};
    assign act_rdata1 = {act_q[3], act_q[2]};

    // Pixel buffer: pixel p in GEN_PIX[p[9:8]] at p[7:0].  The host reads it
    // (rd_src = 2, address h_addr) after DONE; a sequencer write wins.
    wire [7:0] pix_q [0:3];
    wire [7:0] pix_addr = pix_we ? pix_waddr[7:0] : h_addr[7:0];
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : GEN_PIX
            dla_sram_1rw_256x8 u_sram (
                .clk   (clk),
                .we    (pix_we && (pix_waddr[9:8] == gi)),
                .addr  (pix_addr),
                .wdata (pix_wdata),
                .rdata (pix_q[gi])
            );
        end
    endgenerate

    // ---------------------------------------------------------------- read mux
    // rd_data is sampled one clk after rd_req (h_addr stable meanwhile).
    always @* begin
        case (rd_src)
            2'd1:    rd_data = csr_rdata;
            2'd2:    rd_data = pix_q[h_addr[9:8]];
            default: rd_data = 8'h00;           // 3 = INT8 DBG_RD_C: not present
        endcase
    end

    // ---- unused ----
    wire _unused;
    assign _unused = &{1'b0, wb_done_IN, h_addr[15:10], rd_req, dbg_wr_en, dbg_wr_sel,
                        dbg_start, dbg_wr_data, dbg_k_last};

endmodule

`default_nettype wire
