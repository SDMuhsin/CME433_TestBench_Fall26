`timescale 1ns / 1ps
// tb_sat -- mq_sat (50-bit in, widths 8/16/24/raw) vs the spec sat_w.  Vectors "v ww y".
module tb_sat;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg  [51:0] v;
    reg  [1:0]  ww;
    reg  [31:0] exp_y;
    wire [31:0] y;
    mq_sat #(.WI(50)) dut (.v(v[49:0]), .ww(ww), .y(y));

    initial begin
        open_vec("sat");
        while ($fscanf(fd, "%h %h %h\n", v, ww, exp_y) == 3) begin
            #1;
            n = n + 1;
            if (y !== exp_y) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH v=%h ww=%0d y=%h exp=%h", v, ww, y, exp_y);
            end
        end
        report("sat");
    end
endmodule
