`timescale 1ns / 1ps
// fp16_fpu_tb -- fp16_mul + fp32_add_rne (single-cycle composition of the two lane
// adder halves) vs numpy IEEE fp32: sum = RNE32(acc + a*b).
// Vectors: scripts/gen_fp16_unit_vectors.py <dir>  ->  +VEC=<dir>/fpu_vec.hex
module fp16_fpu_tb;
    reg  [15:0] a, b;
    reg  [31:0] acc, exp_s;
    wire [31:0] p, s;
    fp16_mul     u_m (.a(a), .b(b), .p(p));
    fp32_add_rne u_a (.x(acc), .y(p), .s(s));
    integer f, r, n = 0, bad = 0;
    string fn;
    initial begin
        if (!$value$plusargs("VEC=%s", fn)) fn = "sim/results/fp16/unit/fpu_vec.hex";
        f = $fopen(fn, "r");
        if (f == 0) begin $display("FAIL: cannot open %s", fn); $finish; end
        while (!$feof(f)) begin
            r = $fscanf(f, "%h %h %h %h\n", a, b, acc, exp_s);
            if (r != 4) break;
            #1;
            n = n + 1;
            if (s !== exp_s) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH a=%h b=%h acc=%h p=%h got=%h exp=%h", a, b, acc, p, s, exp_s);
            end
        end
        if (bad == 0 && n > 0) $display("PASS: fp16_fpu_tb %0d vectors bit-exact", n);
        else                   $display("FAIL: fp16_fpu_tb %0d/%0d mismatches", bad, n);
        $finish;
    end
endmodule
