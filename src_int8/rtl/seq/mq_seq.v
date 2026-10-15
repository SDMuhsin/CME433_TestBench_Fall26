`timescale 1ns / 1ps

// ============================================================================
// mq_seq -- microcoded token sequencer (ISA: src_int8/ucode/isa.py), the FP16
// chip's two-phase executor with integer operand widths.
//
// Every uop takes two phases; the next uop starts right after P1:
//   P0  stall while the needed stream bytes are missing (use_s: cnt < sw) or
//       the writeback is not ready (use_y: lane busy, or fewer than 3 cycles
//       since it went idle -- mq_wb has three register stages phased by ycnt,
//       exported as wb_ph); then present
//       the memory read (use_m), pop the stream bytes, load the NLU (NLD),
//       and capture the non-memory operand values (side a 32 b, side b 16 b).
//   P1  operands complete (M = memory Q sign-extended by mw, A = side-a
//       value), then execute:
//       MAC  -> lane operand registers, lane issue in the next cycle
//       INIT -> accumulator init register; the next MAC is the first step
//       MOV  -> register file, memory write (width mw), or RQ load (S, sw = 3)
//       END  -> stop (done); LOOPx / eol -> mq_loop
// The writeback controls (mode / shift / width / addend) follow the uop that
// reads Y: a MOV with nstep = 1 reads the NLU result (shift from mq_nlu, zero
// flag), an NLD reads acc raw (32 b).
// ============================================================================
module mq_seq (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,          // run a token step
    input  wire        clr_state,      // run the state-reset routine
    input  wire        abort,          // soft reset: stop
    output reg         run,
    output reg         tok,            // the run is a token step (stream accepted)
    output reg         done,
    output wire [7:0]  upc,
    // stream bytes (LE, up to 3 held)
    input  wire [23:0] s_word,
    input  wire [4:0]  s_cnt,
    output wire        s_pop,
    output wire [1:0]  s_pop_n,
    // memory (1-cycle read latency)
    output wire        m_en,
    output wire        m_we,
    output wire [11:0] m_addr,
    output wire [1:0]  m_mw,
    output wire [23:0] m_wdata,
    input  wire [23:0] m_rdata,
    // MAC lane
    output reg         lane_issue,
    output reg         lane_first,
    output reg  [23:0] lane_a,
    output reg  [15:0] lane_b,
    output reg  [31:0] lane_init,
    output reg  [3:0]  lane_ps,
    output wire        lane_clear,
    input  wire        lane_idle,
    // writeback
    output wire [1:0]  wb_mode,
    output wire [4:0]  wb_sh,
    output reg  [15:0] wb_rq_m,
    output reg  [5:0]  wb_rq_s,
    output wire [15:0] wb_addend,
    output wire [1:0]  wb_ww,
    output wire [1:0]  wb_ph,
    input  wire [31:0] wb_y,
    // nonlinear unit
    output wire        nlu_ld,
    output wire [1:0]  nlu_fn,
    output wire [31:0] nlu_x,
    output wire        nlu_step,
    input  wire [15:0] nlu_a,
    input  wire [11:0] nlu_b,
    input  wire [4:0]  nlu_sh,
    input  wire        nlu_zero
);
`include "mq_ucode_defs.vh"

    // ---------------------------------------------------------------- fetch / decode
    wire [UPC_W-1:0] pc;
    wire [UOP_W-1:0] uop;
    wire [2:0]  op, sa, ra, sb, rb;
    wire [1:0]  eol, sw, mw, wmode, ww;
    wire [3:0]  ps, am;
    wire [4:0]  sh;
    wire [11:0] base;
    wire        wr, wm, nstep, use_s, use_m, use_y;

    mq_ucode_rom u_rom (.pc(pc), .uop(uop));
    mq_uop_dec   u_dec (.uop(uop), .op(op), .eol(eol), .sa(sa), .ra(ra), .sb(sb), .rb(rb),
                        .wr(wr), .wm(wm), .sw(sw), .mw(mw), .ps(ps), .wmode(wmode), .sh(sh),
                        .ww(ww), .nstep(nstep), .base(base), .am(am),
                        .use_s(use_s), .use_m(use_m), .use_y(use_y));

    reg        ph;                             // 0 = P0, 1 = P1
    reg  [1:0] ycnt;                           // cycles the writeback has seen a stable acc
    wire       s_ok = (s_cnt >= {3'd0, sw});
    wire       y_ok = lane_idle && (ycnt == 2'd3);
    assign     wb_ph = ycnt;
    wire       go0  = run && !ph && !(use_s && !s_ok) && !(use_y && !y_ok);
    wire       go1  = run && ph;

    wire [7:0] k, d;
    mq_loop #(.PCW(UPC_W)) u_loop (
        .clk(clk), .rst_n(rst_n), .jump(start | clr_state),
        .entry(start ? ENTRY_TOKEN : ENTRY_RESET),
        .adv(go1 && op != OP_END), .ld0(op == OP_LOOP0), .ld1(op == OP_LOOP1),
        .count(base[7:0]), .eol(eol), .pc(pc), .k(k), .d(d));
    assign upc = pc;

    // ---------------------------------------------------------------- writeback controls
    wire nld   = (op == OP_NLD);
    wire ymode = !nld && nstep;                // MOV dst, YN
    assign wb_mode   = (nld || ymode) ? WM_SH : wmode;
    assign wb_sh     = nld ? 5'd0 : ymode ? nlu_sh : sh;
    assign wb_ww     = nld ? WW_32 : ymode ? WW_16 : ww;
    wire [15:0] qa, qb;
    assign wb_addend = qa;
    wire [31:0] ywb  = (ymode && nlu_zero) ? 32'd0 : wb_y;

    // ---------------------------------------------------------------- operands
    reg  [31:0] va;                            // P0-captured side-a value
    reg  [15:0] vb;                            // P0-captured side-b value

    function [31:0] sext_s(input [23:0] w, input [1:0] n);
        case (n)
            2'd1:    sext_s = {{24{w[7]}}, w[7:0]};
            2'd2:    sext_s = {{16{w[15]}}, w[15:0]};
            default: sext_s = {8'd0, w};               // RQ load: raw 24 b
        endcase
    endfunction

    function [31:0] sext_m(input [23:0] q, input [1:0] w);
        case (w)
            MW_8:    sext_m = {{24{q[7]}}, q[7:0]};
            MW_16:   sext_m = {{16{q[15]}}, q[15:0]};
            default: sext_m = {{8{q[23]}}, q};
        endcase
    endfunction

    function [31:0] src_a(input [2:0] s);
        case (s)
            SRC_EPS: src_a = EPS_VAL;
            SRC_S:   src_a = sext_s(s_word, sw);
            SRC_R:   src_a = {{16{qa[15]}}, qa};
            SRC_Y:   src_a = ywb;
            SRC_N:   src_a = {16'd0, nlu_a};
            default: src_a = 32'd0;                    // Z; M is resolved in P1
        endcase
    endfunction

    function [15:0] src_b(input [2:0] s);
        case (s)
            SRC_S:   src_b = sext_s(s_word, sw);
            SRC_R:   src_b = qb;
            SRC_N:   src_b = {4'd0, nlu_b};
            default: src_b = 16'h0000;                 // Z; M and A are resolved in P1
        endcase
    endfunction

    wire [31:0] mq = sext_m(m_rdata, mw);
    wire [31:0] a1 = (sa == SRC_M) ? mq : va;
    wire [15:0] b1 = (sb == SRC_M) ? mq[15:0] : (sb == SRC_A) ? a1[15:0] : vb;

    mq_regfile u_rf (.clk(clk), .we(go1 && op == OP_MOV && wr), .wa(rb), .wd(a1[15:0]),
                     .ra(ra), .rb(rb), .qa(qa), .qb(qb));

    // ---------------------------------------------------------------- memory, stream, NLU
    wire mem_wr = go1 && op == OP_MOV && wm;
    mq_agu u_agu (.base(base), .am(am), .k(k), .d(d), .addr(m_addr));
    assign m_en    = (go0 && use_m) || mem_wr;
    assign m_we    = mem_wr;
    assign m_mw    = mw;
    assign m_wdata = a1[23:0];
    assign s_pop   = go0 && use_s;
    assign s_pop_n = sw;

    assign nlu_ld   = go0 && nld;
    assign nlu_fn   = wmode;
    assign nlu_x    = (sa == SRC_Y) ? ywb : {{16{qa[15]}}, qa};
    assign nlu_step = nstep;

    assign lane_clear = start | clr_state | abort;

    wire rq_ld = go1 && op == OP_MOV && sa == SRC_S && sw == 2'd3;

    // ---------------------------------------------------------------- control
    reg first_pend;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            run <= 1'b0; tok <= 1'b0; done <= 1'b0; ph <= 1'b0;
            first_pend <= 1'b0; lane_issue <= 1'b0; ycnt <= 2'd0;
        end else begin
            lane_issue <= go1 && op == OP_MAC && !lane_clear;
            if (go0 || !lane_idle || !(run && !ph && use_y)) ycnt <= 2'd0;
            else if (ycnt != 2'd3)                            ycnt <= ycnt + 2'd1;
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
            va <= src_a(sa);
            vb <= src_b(sb);
        end
        if (go1 && op == OP_MAC) begin
            lane_a <= a1[23:0]; lane_b <= b1; lane_ps <= ps; lane_first <= first_pend;
        end
        if (go1 && op == OP_INIT) lane_init <= a1;
        if (rq_ld) begin
            wb_rq_m <= a1[15:0]; wb_rq_s <= a1[21:16];
        end
    end
endmodule
