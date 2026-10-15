`timescale 1ns / 1ps
// tb_nlu -- mb_nlu + mb_lane (two interpolation steps + scaled writeback) vs golden
// nlu.address / nlu.lut, exhaustive over FP16 inputs.  Vectors "fn x idx q scale byp y"
// from src/tb/vectors/nlu.py.  Also checks the registered address fields.
module tb_nlu;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         ld = 1'b0, step = 1'b0, issue = 1'b0;
    reg  [1:0]  fn;
    reg  [15:0] x;
    wire [15:0] a, b, lane_y, y;
    wire [7:0]  scale;
    wire        idle, done, can_issue;
    wire [31:0] acc;

    mb_nlu  u_nlu  (.clk(clk), .ld(ld), .fn(fn), .x(x), .step(step), .a(a), .b(b),
                    .scale(scale), .lane_y(lane_y), .y(y));
    mb_lane u_lane (.clk(clk), .rst_n(rst_n), .clear(1'b0), .issue(issue), .first(!step),
                    .a(a), .b(b), .init(16'h0000), .scale(scale), .can_issue(can_issue),
                    .idle(idle), .done(done), .acc(acc), .y(lane_y));

    task automatic lane_step(input s);
        step = s; issue = 1'b1;
        @(negedge clk);
        issue = 1'b0;
        @(negedge clk);
    endtask

    reg [3:0]  v_fn, v_byp;
    reg [15:0] v_x, v_y;
    reg [11:0] v_idx, v_q;
    reg [7:0]  v_scale;
    initial begin
        open_vec("nlu");
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while ($fscanf(fd, "%h %h %h %h %h %h %h\n", v_fn, v_x, v_idx, v_q, v_scale, v_byp,
                       v_y) == 7) begin
            ld = 1'b1; fn = v_fn[1:0]; x = v_x;
            @(negedge clk);
            ld = 1'b0; x = 16'hxxxx;
            lane_step(1'b0);
            lane_step(1'b1);
            wait (idle);
            @(negedge clk);
            n = n + 1;
            if (y !== v_y || u_nlu.idx_r !== v_idx[8:0] || u_nlu.q_r !== v_q ||
                scale !== v_scale || u_nlu.byp_r !== v_byp[0]) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH fn=%0d x=%h y=%h/%h idx=%0d/%0d q=%0d/%0d s=%0d/%0d byp=%b/%b",
                                        v_fn, v_x, y, v_y, u_nlu.idx_r, v_idx, u_nlu.q_r, v_q,
                                        $signed(scale), $signed(v_scale), u_nlu.byp_r, v_byp[0]);
            end
        end
        report("nlu");
    end
endmodule
