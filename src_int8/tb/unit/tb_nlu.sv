`timescale 1ns / 1ps
// tb_nlu -- mq_nlu + mq_dp (lane + writeback: two interpolation steps, NLU-shift writeback through
// the sequencer's ph 0..3 Y-wait protocol, zero flag) vs the spec 5.1 reference.  Vectors "fn x idx f sh zero y" (tb/ref/vectors.py).  Also checks
// the registered address fields.
module tb_nlu;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg clk = 1'b0, rst_n = 1'b0;
    always #5 clk = ~clk;

    reg         ld = 1'b0, step = 1'b0, issue = 1'b0;
    reg  [1:0]  ph = 2'd0;
    reg  [1:0]  fn;
    reg  [31:0] x;
    wire [15:0] a;
    wire [11:0] b;
    wire [4:0]  sh;
    wire        zero, idle, done;
    wire [31:0] acc, y;

    mq_nlu  u_nlu  (.clk(clk), .ld(ld), .fn(fn), .x(x), .step(step), .a(a), .b(b), .sh(sh), .zero(zero));
    mq_dp   u_dp   (.clk(clk), .rst_n(rst_n), .clear(1'b0), .issue(issue), .first(!step), .w8(1'b0),
                    .a({8'd0, a}), .b({4'd0, b}), .init(32'd0), .ps(4'd0), .idle(idle), .done(done),
                    .acc(acc), .wb_mode(2'd0), .wb_sh(sh), .wb_rq_m(16'h4000), .wb_rq_s(6'd1),
                    .wb_addend(16'd0), .wb_ww(2'd1), .wb_ph(ph), .y(y));
    wire [31:0] out = zero ? 32'd0 : y;

    task automatic lane_step(input s);
        step = s; issue = 1'b1;
        @(negedge clk);
        issue = 1'b0;
        @(negedge clk);
    endtask

    reg [3:0]  v_fn, v_zero;
    reg [31:0] v_x;
    reg [15:0] v_y, v_idx, v_f;
    reg [7:0]  v_sh;
    initial begin
        open_vec("nlu");
        repeat (2) @(negedge clk);
        rst_n = 1'b1;
        while ($fscanf(fd, "%h %h %h %h %h %h %h\n", v_fn, v_x, v_idx, v_f, v_sh, v_zero, v_y) == 7) begin
            ld = 1'b1; fn = v_fn[1:0]; x = v_x;
            @(negedge clk);
            ld = 1'b0; x = 'x;
            lane_step(1'b0);
            lane_step(1'b1);
            wait (idle);                                     // acc final; ph 0: high half
            @(negedge clk); ph = 2'd1;                       // full product
            @(negedge clk); ph = 2'd2;                       // shift / round / saturate
            @(negedge clk); ph = 2'd3; #1;                   // y valid
            n = n + 1;
            // address fields are don't-care when the exp2 zero flag discards the lane result
            if (out !== {{16{v_y[15]}}, v_y} || zero !== v_zero[0] || (!zero &&
                (u_nlu.idx_r !== v_idx[8:0] || u_nlu.f_r !== v_f[11:0] || sh !== v_sh[4:0]))) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH fn=%0d x=%h y=%h/%h idx=%0d/%0d f=%0d/%0d sh=%0d/%0d zero=%b/%b",
                                        v_fn, v_x, out, v_y, u_nlu.idx_r, v_idx, u_nlu.f_r, v_f,
                                        sh, v_sh, zero, v_zero[0]);
            end
            ph = 2'd0;
        end
        report("nlu");
    end
endmodule
