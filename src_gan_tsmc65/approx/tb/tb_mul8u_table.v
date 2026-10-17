`timescale 1ns / 1ps
// Exhaustive vk_mul8u table: prints p(a, b) as 4 hex digits for a, b = 0..255 (a outer).
module tb_mul8u_table;
    reg  [7:0]  a, b;
    wire [15:0] p;
    integer i, j;
    vk_mul8u dut (.a(a), .b(b), .p(p));
    initial begin
        for (i = 0; i < 256; i = i + 1)
            for (j = 0; j < 256; j = j + 1) begin
                a = i; b = j; #1;
                $display("%04x", p);
            end
        $finish;
    end
endmodule
