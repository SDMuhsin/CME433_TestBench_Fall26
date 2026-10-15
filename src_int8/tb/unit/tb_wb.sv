`timescale 1ns / 1ps
// tb_wb -- mq_wb with the mq_mul24x17 it borrows from mq_dp while the lane is idle, vs the
// spec wb_sh / wb_rq + addend + sat_w.  Vectors "acc mode sh m s addend ww y" (tb/ref/vectors.py).
// One vector per 4 cycles, following the sequencer's Y-wait protocol: inputs stable with
// ph = 0, 1, 2 (high half, full product, shift / round / addend / saturate), y read at ph = 3.
module tb_wb;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg  [31:0] acc = 0;
    reg  [1:0]  mode = 0, ww = 0, ph = 0;
    reg  [4:0]  sh = 0;
    reg  [15:0] m = 16'h4000, addend = 0;
    reg  [5:0]  s = 1;
    wire [31:0] y;
    wire [23:0] ma;
    wire [16:0] mb;
    wire [40:0] p;
    // mq_dp with the lane idle: the multiplier belongs to the writeback
    mq_mul24x17 u_mul (.a(ma), .b(mb), .p(p));
    mq_wb dut (.clk(clk), .acc(acc), .mode(mode), .sh(sh), .rq_m(m), .rq_s(s), .addend(addend),
               .ww(ww), .ph(ph), .ma(ma), .mb(mb), .p(p), .y(y));

    reg [31:0] v_acc, v_y, v_m, v_add;
    reg [7:0]  v_mode, v_sh, v_s, v_ww;

    initial begin
        open_vec("wb");
        @(negedge clk);
        while ($fscanf(fd, "%h %h %h %h %h %h %h %h\n", v_acc, v_mode, v_sh, v_m, v_s, v_add,
                       v_ww, v_y) == 8) begin
            acc = v_acc; mode = v_mode[1:0]; sh = v_sh[4:0]; m = v_m[15:0]; s = v_s[5:0];
            addend = v_add[15:0]; ww = v_ww[1:0];
            ph = 2'd0; @(negedge clk);
            ph = 2'd1; @(negedge clk);
            ph = 2'd2; @(negedge clk);
            ph = 2'd3; #1;
            n = n + 1;
            if (y !== v_y) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH vec %0d acc=%h mode=%0d sh=%0d m=%h s=%0d add=%h ww=%0d y=%h exp=%h",
                                        n - 1, acc, mode, sh, m, s, addend, ww, y, v_y);
            end
            @(negedge clk);
        end
        report("wb");
    end
endmodule
