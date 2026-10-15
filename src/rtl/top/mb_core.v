`timescale 1ns / 1ps

// ============================================================================
// mb_core -- Mamba token engine: stream FIFO -> microcoded sequencer -> one
// FP16xFP16->FP32 MAC lane + shared nonlinear unit, with the FP16 state and
// activations in 10 SRAM macros (5 hi/lo pairs).
//
//   start      run one token step (the host then streams TOKEN_BYTES bytes)
//   clr_state  run the state-reset routine (zero H*, CONV*)
//   abort      soft reset (stop)
// HRDY: high when idle; during a token step high iff the FIFO has room and
// the token's bytes are not all received; low while the state reset runs.
// The host reads memory bytes (logits) through mb_mem_arb when idle.
// ============================================================================
module mb_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        clr_state,
    input  wire        abort,
    input  wire [7:0]  st_byte,
    input  wire        st_valid,
    input  wire        h_req,
    input  wire [11:0] h_addr,
    output wire [7:0]  h_rdata,
    output wire        hrdy,
    output wire        busy,
    output wire        done,
    output wire        tok,
    output wire        err_ovf,
    output wire [19:0] byte_cnt,
    output wire [7:0]  upc
);
`include "mb_ucode_defs.vh"

    // ---------------------------------------------------------------- stream
    wire [15:0] s_word;
    wire        s_ok, s_pop, room, all_rcvd;

    mb_stream_fifo #(.TOTAL(TOKEN_BYTES)) u_fifo (
        .clk(clk), .rst_n(rst_n), .clr(start | clr_state | abort), .arm(busy && tok),
        .st_byte(st_byte), .st_valid(st_valid), .pop(s_pop), .word(s_word), .word_ok(s_ok),
        .room(room), .all_rcvd(all_rcvd), .byte_cnt(byte_cnt), .err_ovf(err_ovf));

    assign hrdy = !busy || (tok && !all_rcvd && room);

    // ---------------------------------------------------------------- sequencer
    wire        s_en, s_we;
    wire [10:0] s_addr;
    wire [15:0] s_wdata, m_rdata;
    wire        l_issue, l_first, l_clear, l_idle;
    wire [15:0] l_a, l_b, l_init, l_y;
    wire signed [7:0] l_scale, n_scale;
    wire        n_ld, n_step;
    wire [1:0]  n_fn;
    wire [15:0] n_x, n_a, n_b, n_y;

    mb_seq u_seq (
        .clk(clk), .rst_n(rst_n), .start(start), .clr_state(clr_state), .abort(abort),
        .run(busy), .tok(tok), .done(done), .upc(upc),
        .s_word(s_word), .s_ok(s_ok), .s_pop(s_pop),
        .m_en(s_en), .m_we(s_we), .m_addr(s_addr), .m_wdata(s_wdata), .m_rdata(m_rdata),
        .lane_issue(l_issue), .lane_first(l_first), .lane_a(l_a), .lane_b(l_b),
        .lane_init(l_init), .lane_scale(l_scale), .lane_clear(l_clear), .lane_idle(l_idle),
        .lane_y(l_y),
        .nlu_ld(n_ld), .nlu_fn(n_fn), .nlu_x(n_x), .nlu_step(n_step), .nlu_a(n_a),
        .nlu_b(n_b), .nlu_scale(n_scale), .nlu_y(n_y));

    // ---------------------------------------------------------------- datapath
    mb_lane u_lane (
        .clk(clk), .rst_n(rst_n), .clear(l_clear), .issue(l_issue), .first(l_first),
        .a(l_a), .b(l_b), .init(l_init), .scale(l_scale), .can_issue(), .idle(l_idle),
        .done(), .acc(), .y(l_y));

    mb_nlu u_nlu (
        .clk(clk), .ld(n_ld), .fn(n_fn), .x(n_x), .step(n_step), .a(n_a), .b(n_b),
        .scale(n_scale), .lane_y(l_y), .y(n_y));

    // ---------------------------------------------------------------- memory
    wire        m_en, m_we;
    wire [10:0] m_addr;

    mb_mem_arb u_arb (
        .clk(clk), .seq_own(busy), .s_en(s_en), .s_we(s_we), .s_addr(s_addr),
        .h_req(h_req), .h_addr(h_addr), .h_rdata(h_rdata),
        .m_en(m_en), .m_we(m_we), .m_addr(m_addr), .m_rdata(m_rdata));

    mb_mem u_mem (
        .clk(clk), .en(m_en), .we(m_we), .addr(m_addr), .wdata(s_wdata), .rdata(m_rdata));
endmodule
