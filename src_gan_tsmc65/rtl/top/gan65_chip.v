`timescale 1ns / 1ps
`default_nettype none
`include "gan65_cfg.vh"

// ============================================================================
// gan65_chip -- END-TO-END G300 GAN generator core for 65 nm (synthesis top).
//
// Technology-clean copy of rtl/dla_e2e_chip.sv: identical logic, but the GF180
// bi_24t pad-control terminals (PU/PD/CS/SL/IE per pad) are dropped and the
// quad IO is exposed as plain in/out/oe buses; the pad ring is added at
// integration.  Memories: A/B buffers = 8 x dla_sram_1rw_256x8 (latch RF,
// mem/), C buffer = flip-flops.  Host protocol, CSR map and stream layout are
// unchanged (docs/dla_e2e_chip.md):
//   sclk, cs_n      : SPI mode-0 host clock / select (2FF-synchronised inside)
//   io_in/out/oe    : quad IO[3:0]; IO0 = MOSI, IO1 = MISO
//   hrdy            : host ready / image done
// Single clock domain (clk); rst_n asynchronous active low.
//
// Datapath width DATA_W = `GAN65_DATA_W (rtl/cfg/w8 | w16 on the include path,
// docs/width16.md): A/B words, multipliers, requant operands are DATA_W bits,
// the accumulators ACC_W = 2*DATA_W + 8.  The host protocol stays byte based:
// stream elements and debug writes are DATA_W/8 bytes (little endian), a C
// debug read returns 4 (DATA_W = 8) or 8 bytes per accumulator, and pixels
// are 8-bit (one byte each) at every width.
// ============================================================================
module gan65_chip (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       sclk,
    input  wire       cs_n,
    input  wire [3:0] io_in,
    output wire [3:0] io_out,
    output wire [3:0] io_oe,
    output wire       hrdy
);
    `include "g300_quant_params.vh"
    localparam integer DATA_W = `GAN65_DATA_W;
    localparam integer ACC_W  = 2 * DATA_W + 8;        // 256-term dot products of 2*DATA_W-bit products
    localparam integer NB     = DATA_W / 8;            // bytes per stream / debug element
    localparam integer CB_L   = (ACC_W > 32) ? 3 : 2;  // log2 bytes per C debug word
    localparam integer BC_W   = $clog2(283984 * NB + 1);
    localparam integer REQ_S  = G300_REQ_SHIFT;


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
        .sclk_pad    (sclk),
        .cs_n_pad    (cs_n),
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
    wire [BC_W-1:0] s_byte_cnt;

    e2e_csr #(.BC_W(BC_W)) u_csr (
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
    wire [DATA_W-1:0] dla_wr_data;
    wire [3:0]  dla_rd_addr;
    wire signed [ACC_W-1:0] dla_rd_data;
    wire        dla_wb_done, dla_done, dla_busy;
    wire        dla_active;
    wire [4*DATA_W-1:0] b_rd_data;
    wire [7:0]  stash_rd_data;

    // debug writes: host bytes -> DATA_W-bit A/B elements
    wire              dbg_el_we;
    wire [9:0]        dbg_el_addr;
    wire [DATA_W-1:0] dbg_el_data;
    e2e_dbg_pack #(.NB(NB)) u_dbg (
        .clk     (clk),
        .wr_en   (dbg_wr_en),
        .h_addr  (h_addr),
        .wr_byte (dbg_wr_data),
        .el_we   (dbg_el_we),
        .el_addr (dbg_el_addr),
        .el_data (dbg_el_data)
    );

    e2e_seq #(
        .DATA_W (DATA_W),
        .ACC_W  (ACC_W),
        .REQ_S  (REQ_S),
        .BC_W   (BC_W)
    ) u_seq (
        .clk           (clk),
        .rst_n         (rst_n),
        .soft_rst      (soft_rst),
        .start_cmd     (seq_start_cmd),
        .st_byte       (st_byte),
        .st_valid      (st_valid),
        .err_cmd_in    (err_cmd_p),
        .ma0 (ma0), .mb0 (mb0), .ma2 (ma2), .mb2 (mb2), .mw4 (mw4), .mb4 (mb4),
        .dbg_wr_en     (dbg_el_we),
        .dbg_wr_sel    (dbg_wr_sel),
        .dbg_wr_addr   (dbg_el_addr),
        .dbg_wr_data   (dbg_el_data),
        .dbg_start     (dbg_start),
        .dbg_k_last    (dbg_k_last),
        .dbg_rd_en     (rd_src == 2'd3),
        .dbg_rd_addr   (h_addr[CB_L+3:CB_L]),
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
        .DATA_W  (DATA_W),
        .ACC_W   (ACC_W),
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
    // (the pixel is the low byte of the DATA_W-bit B word)
    reg [7:0] pix_b;
    always @* begin
        case (h_addr[9:8])
            2'd0:    pix_b = b_rd_data[1*DATA_W +: 8];
            2'd1:    pix_b = b_rd_data[2*DATA_W +: 8];
            default: pix_b = b_rd_data[3*DATA_W +: 8];
        endcase
    end
    wire       pix_tail = (h_addr[9:8] == 2'd3);
    wire [7:0] pix_data = pix_tail ? stash_rd_data : pix_b;

    // C debug read: byte h_addr[CB_L-1:0] of the sign-extended accumulator, little endian
    wire signed [8*(1<<CB_L)-1:0] c_word = dla_rd_data;
    wire [7:0] c_byte = c_word[8*h_addr[CB_L-1:0] +: 8];

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
    assign _unused = &{1'b0, dla_done, dla_busy, pe_col_gate_en, h_addr[15:10],
                        rd_req, b_rd_data};

endmodule

`default_nettype wire
