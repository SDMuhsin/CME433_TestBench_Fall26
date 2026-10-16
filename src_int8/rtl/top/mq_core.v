`timescale 1ns / 1ps

// ============================================================================
// mq_core -- INT8 Mamba token engine: stream FIFO -> microcoded sequencer ->
// one INT24 x INT16 -> INT32 MAC lane and requantising writeback sharing one
// multiplier (mq_dp) + shared LUT unit, with the INT24 state and INT8/INT16 activations in 11 SRAM macros.
//
//   start      run one token step (the host then streams TOKEN_BYTES bytes)
//   clr_state  run the state-reset routine (zero H0, H1, CONV0, CONV1)
//   abort      soft reset (stop)
// HRDY: high when idle; during a token step high iff the FIFO has room and
// the token's bytes are not all received; low while the state reset runs.
// The host reads memory bytes (logits) through mq_mem_arb when idle.
// ============================================================================
module mq_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        clr_state,
    input  wire        abort,
    input  wire [7:0]  st_byte,
    input  wire        st_valid,
    input  wire        h_req,
    input  wire [12:0] h_addr,
    output wire [7:0]  h_rdata,
    output wire        hrdy,
    output wire        busy,
    output wire        done,
    output wire        tok,
    output wire        err_ovf,
    output wire [19:0] byte_cnt,
    output wire [7:0]  upc
);
`include "mq_ucode_defs.vh"

    // ---------------------------------------------------------------- stream
    wire [23:0] s_word;
    wire [4:0]  s_cnt;
    wire        s_pop, room, all_rcvd;
    wire [1:0]  s_pop_n;

    mq_stream_fifo #(.TOTAL(TOKEN_BYTES)) u_fifo (
        .clk(clk), .rst_n(rst_n), .clr(start | clr_state | abort), .arm(busy && tok),
        .st_byte(st_byte), .st_valid(st_valid), .pop(s_pop), .pop_n(s_pop_n), .word(s_word),
        .cnt(s_cnt), .room(room), .all_rcvd(all_rcvd), .byte_cnt(byte_cnt), .err_ovf(err_ovf));

    assign hrdy = !busy || (tok && !all_rcvd && room);

    // ---------------------------------------------------------------- sequencer
    wire        s_en, s_we;
    wire [11:0] s_addr;
    wire [1:0]  s_mw;
    wire [23:0] s_wdata, m_rdata;
    wire        l_issue, l_first, l_w8, l_clear, l_idle;
    wire [23:0] l_a;
    wire [15:0] l_b;
    wire [31:0] l_init, l_acc, w_y;
    wire [3:0]  l_ps;
    wire [1:0]  w_mode, w_ww, w_ph;
    wire [4:0]  w_sh, n_sh;
    wire [15:0] w_rq_m, w_addend, n_a;
    wire [5:0]  w_rq_s;
    wire        n_ld, n_step, n_zero;
    wire [1:0]  n_fn;
    wire [31:0] n_x;
    wire [11:0] n_b;

    mq_seq u_seq (
        .clk(clk), .rst_n(rst_n), .start(start), .clr_state(clr_state), .abort(abort),
        .run(busy), .tok(tok), .done(done), .upc(upc),
        .s_word(s_word), .s_cnt(s_cnt), .s_pop(s_pop), .s_pop_n(s_pop_n),
        .m_en(s_en), .m_we(s_we), .m_addr(s_addr), .m_mw(s_mw), .m_wdata(s_wdata),
        .m_rdata(m_rdata),
        .lane_issue(l_issue), .lane_first(l_first), .lane_w8(l_w8), .lane_a(l_a), .lane_b(l_b),
        .lane_init(l_init), .lane_ps(l_ps), .lane_clear(l_clear), .lane_idle(l_idle),
        .wb_mode(w_mode), .wb_sh(w_sh), .wb_rq_m(w_rq_m), .wb_rq_s(w_rq_s),
        .wb_addend(w_addend), .wb_ww(w_ww), .wb_ph(w_ph), .wb_y(w_y),
        .nlu_ld(n_ld), .nlu_fn(n_fn), .nlu_x(n_x), .nlu_step(n_step), .nlu_a(n_a),
        .nlu_b(n_b), .nlu_sh(n_sh), .nlu_zero(n_zero));

    // ---------------------------------------------------------------- datapath
    mq_dp u_dp (
        .clk(clk), .rst_n(rst_n), .clear(l_clear), .issue(l_issue), .first(l_first), .w8(l_w8),
        .a(l_a), .b(l_b), .init(l_init), .ps(l_ps), .idle(l_idle), .done(), .acc(l_acc),
        .wb_mode(w_mode), .wb_sh(w_sh), .wb_rq_m(w_rq_m), .wb_rq_s(w_rq_s),
        .wb_addend(w_addend), .wb_ww(w_ww), .wb_ph(w_ph), .y(w_y));

    mq_nlu u_nlu (
        .clk(clk), .ld(n_ld), .fn(n_fn), .x(n_x), .step(n_step), .a(n_a), .b(n_b),
        .sh(n_sh), .zero(n_zero));

    // ---------------------------------------------------------------- memory
    wire        m_en, m_we;
    wire [11:0] m_addr;
    wire [1:0]  m_mw;

    mq_mem_arb u_arb (
        .clk(clk), .seq_own(busy), .s_en(s_en), .s_we(s_we), .s_addr(s_addr), .s_mw(s_mw),
        .h_req(h_req), .h_addr(h_addr), .h_rdata(h_rdata),
        .m_en(m_en), .m_we(m_we), .m_addr(m_addr), .m_mw(m_mw), .m_rdata(m_rdata));

    mq_mem u_mem (
        .clk(clk), .en(m_en), .we(m_we), .addr(m_addr), .mw(m_mw), .wdata(s_wdata),
        .rdata(m_rdata));
endmodule
