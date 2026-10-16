`timescale 1ns / 1ps
// Exhaustive table of mq_mul8: prints p for a, b = -128..127 (row-major in a), one hex word a line.
module tb_mul8_table;
    reg  signed [7:0]  a, b;
    wire signed [15:0] p;
    integer i, j;
    mq_mul8 dut (.a(a), .b(b), .p(p));
    initial begin
        for (i = -128; i < 128; i = i + 1)
            for (j = -128; j < 128; j = j + 1) begin
                a = i; b = j; #1;
                $display("%h", p);
            end
        $finish;
    end
endmodule
