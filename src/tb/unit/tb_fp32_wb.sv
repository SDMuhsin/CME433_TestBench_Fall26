`timescale 1ns / 1ps
// tb_fp32_wb -- mb_fp32_wb vs golden fp.writeback(acc, scale).
// Vectors "acc scale y" from src/tb/vectors/wb.py.
module tb_fp32_wb;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg  [31:0] acc;
    reg  [7:0]  scale;
    reg  [15:0] exp_y;
    wire [15:0] y;
    mb_fp32_wb dut (.acc(acc), .scale(scale), .y(y));

    initial begin
        open_vec("fp32_wb");
        while ($fscanf(fd, "%h %h %h\n", acc, scale, exp_y) == 3) begin
            #1;
            n = n + 1;
            if (y !== exp_y) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH acc=%h scale=%h y=%h exp=%h", acc, scale, y, exp_y);
            end
        end
        report("fp32_wb");
    end
endmodule
