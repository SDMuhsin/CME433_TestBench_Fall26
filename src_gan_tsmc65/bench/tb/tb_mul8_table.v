`timescale 1ns / 1ps
// Exhaustive gan_mul8 table: prints p(a, b) as 4 hex digits for a, b = -128..127 (a outer).
module tb_mul8_table;
    reg  signed [7:0]  a, b;
    wire signed [15:0] p;
    integer i, j;
    gan_mul8 dut (.a(a), .b(b), .p(p));
    initial begin
        for (i = -128; i < 128; i = i + 1)
            for (j = -128; j < 128; j = j + 1) begin
                a = i; b = j; #1;
                $display("%04x", p);
            end
        $finish;
    end
endmodule
