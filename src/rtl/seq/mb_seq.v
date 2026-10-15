`timescale 1ns / 1ps

// ============================================================================
// mb_seq -- microcoded token sequencer (ISA: src/ucode/isa.py).
//
// Every uop takes two phases; the next uop starts right after P1:
//   P0  stall while a needed stream word is missing (use_s) or the lane is
//       still busy (use_y); then present the SRAM read (use_m), pop the stream
//       word, load the NLU (NLD), and capture the non-memory operand values.
//   P1  operands complete (M = SRAM Q, A = side-A value), then execute:
//       MAC  -> lane operand registers, lane issue in the next cycle
//       INIT -> accumulator init register; the next MAC is the first step
//       MOV  -> register file and/or SRAM write
//       END  -> stop (done); LOOPx / eol -> mb_loop
// Lane operands always come from registers (lane_a/b/init), as mb_lane needs.
// Uops are >= 2 cycles apart, so lane issues are too (mb_lane interval rule).
// The lane writeback scale follows `mode` of the current uop (MOV Y.*).
// ============================================================================
module mb_seq (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          // run a token step
    input  wire        clr_state,      // run the state-reset routine
    input  wire        abort,          // soft reset: stop
    output reg         run,
    output reg         tok,            // the run is a token step (stream accepted)
    output reg         done,
    output wire [7:0]  upc,
    // stream words
    input  wire [15:0] s_word,
    input  wire        s_ok,
    output wire        s_pop,
    // FP16 memory (1-cycle read latency)
    output wire        m_en,
    output wire        m_we,
    output wire [10:0] m_addr,
    output wire [15:0] m_wdata,
    input  wire [15:0] m_rdata,
    // MAC lane
    output reg         lane_issue,
    output reg         lane_first,
    output reg  [15:0] lane_a,
    output reg  [15:0] lane_b,
    output reg  [15:0] lane_init,
    output wire signed [7:0] lane_scale,
    output wire        lane_clear,
    input  wire        lane_idle,
    input  wire [15:0] lane_y,
    // nonlinear unit
    output wire        nlu_ld,
    output wire [1:0]  nlu_fn,
    output wire [15:0] nlu_x,
    output wire        nlu_step,
    input  wire [15:0] nlu_a,
    input  wire [15:0] nlu_b,
    input  wire signed [7:0] nlu_scale,
    input  wire [15:0] nlu_y
);
`include "mb_ucode_defs.vh"

    // ---------------------------------------------------------------- fetch / decode
    wire [UPC_W-1:0] pc;
    wire [UOP_W-1:0] uop;
    wire [2:0]  op, sa, ra, sb, rb, am;
    wire [1:0]  eol, mode;
    wire [10:0] base;
    wire        wr, wm, nstep, use_s, use_m, use_y;

    mb_ucode_rom u_rom (.pc(pc), .uop(uop));
    mb_uop_dec   u_dec (.uop(uop), .op(op), .eol(eol), .sa(sa), .ra(ra), .sb(sb), .rb(rb),
                        .wr(wr), .wm(wm), .mode(mode), .nstep(nstep), .base(base), .am(am),
                        .use_s(use_s), .use_m(use_m), .use_y(use_y));

    reg  ph;                                   // 0 = P0, 1 = P1
    wire go0 = run && !ph && !(use_s && !s_ok) && !(use_y && !lane_idle);
    wire go1 = run && ph;

    wire [7:0] k, d;
    mb_loop #(.PCW(UPC_W)) u_loop (
        .clk(clk), .rst_n(rst_n), .jump(start | clr_state),
        .entry(start ? ENTRY_TOKEN : ENTRY_RESET),
        .adv(go1 && op != OP_END), .ld0(op == OP_LOOP0), .ld1(op == OP_LOOP1),
        .count(base[7:0]), .eol(eol), .pc(pc), .k(k), .d(d));
    assign upc = pc;                           // zero-extended (UPC_W <= 8)

    // ---------------------------------------------------------------- operands
    wire [15:0] qa, qb;
    reg  [15:0] va, vb;                        // P0-captured operand values
    wire [15:0] ywb = (mode == MODE_WBN) ? nlu_y : lane_y;

    assign lane_scale = (mode == MODE_WBN) ? nlu_scale : (mode == MODE_WB6) ? -8'sd6 : 8'sd0;

    function [15:0] src_val(input [2:0] s, input [15:0] rq, input [15:0] nq);
        case (s)
            SRC_EPS: src_val = EPS_BITS;
            SRC_S:   src_val = s_word;
            SRC_R:   src_val = rq;
            SRC_Y:   src_val = ywb;
            SRC_N:   src_val = nq;
            default: src_val = 16'h0000;       // Z; M and A are resolved in P1
        endcase
    endfunction

    wire [15:0] a1 = (sa == SRC_M) ? m_rdata : va;
    wire [15:0] b1 = (sb == SRC_M) ? m_rdata : (sb == SRC_A) ? a1 : vb;

    mb_regfile u_rf (.clk(clk), .we(go1 && op == OP_MOV && wr), .wa(rb), .wd(a1),
                     .ra(ra), .rb(rb), .qa(qa), .qb(qb));

    // ---------------------------------------------------------------- memory, stream, NLU
    wire mem_wr = go1 && op == OP_MOV && wm;
    mb_agu u_agu (.base(base), .am(am), .k(k), .d(d), .addr(m_addr));
    assign m_en    = (go0 && use_m) || mem_wr;
    assign m_we    = mem_wr;
    assign m_wdata = a1;
    assign s_pop   = go0 && use_s;

    assign nlu_ld   = go0 && op == OP_NLD;
    assign nlu_fn   = mode;
    assign nlu_x    = qa;
    assign nlu_step = nstep;

    assign lane_clear = start | clr_state | abort;

    // ---------------------------------------------------------------- control
    reg first_pend;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run <= 1'b0; tok <= 1'b0; done <= 1'b0; ph <= 1'b0;
            first_pend <= 1'b0; lane_issue <= 1'b0;
        end else begin
            lane_issue <= go1 && op == OP_MAC && !lane_clear;
            if (start | clr_state) begin
                run <= 1'b1; tok <= start; done <= 1'b0; ph <= 1'b0; first_pend <= 1'b0;
            end else if (abort) begin
                run <= 1'b0; tok <= 1'b0; ph <= 1'b0;
            end else if (go0) begin
                ph <= 1'b1;
            end else if (go1) begin
                ph <= 1'b0;
                if (op == OP_INIT) first_pend <= 1'b1;
                if (op == OP_MAC)  first_pend <= 1'b0;
                if (op == OP_END) begin
                    run <= 1'b0; tok <= 1'b0; done <= 1'b1;
                end
            end
        end
    end

    // datapath registers (no reset)
    always @(posedge clk) begin
        if (go0) begin
            va <= src_val(sa, qa, nlu_a);
            vb <= src_val(sb, qb, nlu_b);
        end
        if (go1 && op == OP_MAC) begin
            lane_a <= a1; lane_b <= b1; lane_first <= first_pend;
        end
        if (go1 && op == OP_INIT) lane_init <= a1;
    end
endmodule
