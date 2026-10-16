`timescale 1ns / 1ps
// tb_lane -- mq_lane (through mq_dp, which holds the multiplier) step by step vs the spec
// mac().  Vectors "first a b init ps acc" (tb/ref/vectors.py).  Steps issue at the maximum rate
// (every 2 cycles) with random extra gaps; a scoreboard checks acc on every `done`.  `init` is
// held through the cycle after the issue (the lane reads it in S2); the writeback is idle.
module tb_lane;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         issue = 1'b0, first = 1'b0;
    reg  [23:0] a;
    reg  [15:0] b;
    reg  [31:0] init;
    reg  [3:0]  ps;
    wire [31:0] acc;
    wire        done, idle;

    reg  [31:0] q_acc [0:3];                    // scoreboard (at most 2 steps in flight)
    integer     wr = 0, rd = 0;

    wire [31:0] y;
    mq_dp dut (.clk(clk), .rst_n(rst_n), .clear(1'b0), .issue(issue), .first(first), .w8(1'b0),
               .a(a), .b(b), .init(init), .ps(ps), .idle(idle), .done(done), .acc(acc),
               .wb_mode(2'd0), .wb_sh(5'd0), .wb_rq_m(16'd0), .wb_rq_s(6'd0), .wb_addend(16'd0),
               .wb_ww(2'd0), .wb_ph(2'd0), .y(y));

    reg [3:0]  v_first, v_ps;
    reg [23:0] v_a;
    reg [15:0] v_b;
    reg [31:0] v_init, v_acc;
    initial begin
        open_vec("lane");
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while ($fscanf(fd, "%h %h %h %h %h %h\n", v_first, v_a, v_b, v_init, v_ps, v_acc) == 6) begin
            @(negedge clk);
            q_acc[wr % 4] = v_acc;
            wr = wr + 1;
            issue = 1'b1; first = v_first[0]; a = v_a; b = v_b; init = v_init; ps = v_ps;
            @(negedge clk);
            issue = 1'b0; a = 'x; b = 'x; ps = 'x;
            if (($random & 3) == 0) @(negedge clk);
        end
        wait (rd == wr && idle);
        report("lane");
    end

    always @(posedge clk) begin
        if (done) begin
            n = n + 1;
            if (acc !== q_acc[rd % 4]) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH step %0d acc=%h exp=%h", rd, acc, q_acc[rd % 4]);
            end
            rd = rd + 1;
        end
    end
endmodule
