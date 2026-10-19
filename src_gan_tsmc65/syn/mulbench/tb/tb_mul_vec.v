`timescale 1ns / 1ps
// Vector check of a mul_core design (iverilog, -Ptb_mul_vec.N=8|16): reads one hex word {a, b}
// (2N bits) per line from +VEC=<file>, prints p (2N bits, hex) per vector.
// Used by approx/mulbench_check.py.
module tb_mul_vec;
    parameter N = 16;
    reg  [N - 1:0] a, b;
    wire [2 * N - 1:0] p;
    mul_core dut (.a(a), .b(b), .p(p));
    reg [2 * N - 1:0] w;
    integer fd;
    reg [1023:0] vec;
    initial begin
        if (!$value$plusargs("VEC=%s", vec)) $finish;
        fd = $fopen(vec, "r");
        while ($fscanf(fd, "%h\n", w) == 1) begin
            {a, b} = w;
            #1 $display("%h", p);
        end
        $fclose(fd);
        $finish;
    end
endmodule
