`timescale 1ns / 1ps
// tb_fp16_to_fp32 -- mb_fp16_to_fp32 vs golden value(canon16(h)), all 65536 codes.
// Vectors "h f" from src/tb/vectors/fpu.py.
module tb_fp16_to_fp32;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg  [15:0] h;
    reg  [31:0] exp_f;
    wire [31:0] f;
    mb_fp16_to_fp32 dut (.h(h), .f(f));

    initial begin
        open_vec("fp16_to_fp32");
        while ($fscanf(fd, "%h %h\n", h, exp_f) == 2) begin
            #1;
            n = n + 1;
            if (f !== exp_f) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH h=%h f=%h exp=%h", h, f, exp_f);
            end
        end
        report("fp16_to_fp32");
    end
endmodule
