`timescale 1ns / 1ps
// tb_lane -- mb_lane step by step vs golden fp.mac / fp.writeback.
// Vectors "first a b init scale acc y" from src/tb/vectors/lane.py.  Steps issue at the
// maximum rate (every 2 cycles) with random extra gaps; a scoreboard checks acc and y on
// every `done`, with the lane scale input taken from the step being completed.
module tb_lane;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         issue = 1'b0, first = 1'b0;
    reg  [15:0] a, b, init;
    wire [31:0] acc;
    wire [15:0] y;
    wire        done, idle, can_issue;

    // scoreboard (at most 2 steps in flight)
    reg  [7:0]  q_scale [0:3];
    reg  [31:0] q_acc   [0:3];
    reg  [15:0] q_y     [0:3];
    integer     wr = 0, rd = 0;

    mb_lane dut (.clk(clk), .rst_n(rst_n), .clear(1'b0), .issue(issue), .first(first),
                 .a(a), .b(b), .init(init), .scale(q_scale[rd % 4]), .can_issue(can_issue),
                 .idle(idle), .done(done), .acc(acc), .y(y));

    reg [3:0]  v_first;
    reg [15:0] v_a, v_b, v_init, v_y;
    reg [7:0]  v_scale;
    reg [31:0] v_acc;
    initial begin
        open_vec("lane");
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while ($fscanf(fd, "%h %h %h %h %h %h %h\n", v_first, v_a, v_b, v_init, v_scale,
                       v_acc, v_y) == 7) begin
            @(negedge clk);
            q_scale[wr % 4] = v_scale; q_acc[wr % 4] = v_acc; q_y[wr % 4] = v_y;
            wr = wr + 1;
            issue = 1'b1; first = v_first[0]; a = v_a; b = v_b; init = v_init;
            @(negedge clk);
            issue = 1'b0;
            if (($random & 3) == 0) @(negedge clk);
        end
        wait (rd == wr && idle);
        report("lane");
    end

    always @(posedge clk) begin
        if (done) begin
            n = n + 1;
            if (acc !== q_acc[rd % 4] || y !== q_y[rd % 4]) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH step %0d acc=%h/%h y=%h/%h", rd, acc,
                                        q_acc[rd % 4], y, q_y[rd % 4]);
            end
            rd = rd + 1;
        end
    end
endmodule
