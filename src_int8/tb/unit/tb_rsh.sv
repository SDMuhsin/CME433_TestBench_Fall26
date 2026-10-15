`timescale 1ns / 1ps
// tb_rsh -- mq_rsh (40 -> 32, k 0..15) vs the spec rsh(v, k): y = q + rbit.  Vectors "v k y"
// (tb/ref/vectors.py).
module tb_rsh;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg  [39:0] v;
    reg  [3:0]  k;
    reg  [31:0] exp_y;
    wire [31:0] q, y;
    wire        rbit;
    mq_rsh #(.WI(40), .WO(32), .KW(4)) dut (.v(v), .k(k), .q(q), .rbit(rbit));
    assign y = q + {31'd0, rbit};

    initial begin
        open_vec("rsh");
        while ($fscanf(fd, "%h %h %h\n", v, k, exp_y) == 3) begin
            #1;
            n = n + 1;
            if (y !== exp_y) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH v=%h k=%0d y=%h exp=%h", v, k, y, exp_y);
            end
        end
        report("rsh");
    end
endmodule
