`timescale 1ns / 1ps
// tb_fpu_mac -- mb_fp16_mul (exact product) + mb_fp32_add_rne vs golden fp.mac.
// Vectors "a b acc p sum" from src/tb/vectors/fpu.py.
module tb_fpu_mac;
    integer fd, n, bad;
    string vec;
    `include "tb_report.svh"

    reg  [15:0] a, b;
    reg  [31:0] acc, exp_p, exp_s;
    wire [31:0] p, s;
    mb_fp16_mul     u_mul (.a(a), .b(b), .p(p));
    mb_fp32_add_rne u_add (.x(acc), .y(p), .s(s));

    initial begin
        open_vec("fpu_mac");
        while ($fscanf(fd, "%h %h %h %h %h\n", a, b, acc, exp_p, exp_s) == 5) begin
            #1;
            n = n + 1;
            if (p !== exp_p || s !== exp_s) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH a=%h b=%h acc=%h p=%h/%h s=%h/%h",
                                        a, b, acc, p, exp_p, s, exp_s);
            end
        end
        report("fpu_mac");
    end
endmodule
