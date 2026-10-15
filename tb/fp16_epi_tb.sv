`timescale 1ns / 1ps
// fp16_epi_tb -- FP32 -> FP16 (FTZ/RNE/sat), ReLU and tanh-pixel threshold search vs
// scripts/fp16_golden.py.  Includes every legal FP16 value in tanh mode (exhaustive ROM).
// Vectors: scripts/gen_fp16_unit_vectors.py <dir>  ->  +VEC=<dir>/epi_vec.hex
module fp16_epi_tb;
    reg clk = 0, rst_n = 0, go = 0, mode = 0;
    reg [31:0] acc;
    wire [15:0] y; wire [7:0] pix; wire busy, done;
    always #5 clk = ~clk;
    fp16_epi dut (.clk(clk), .rst_n(rst_n), .clear(1'b0), .go(go), .tanh_mode(mode), .acc(acc),
                  .y(y), .pix(pix), .busy(busy), .done(done));
    integer f, r, n = 0, bad = 0, lat, m;
    reg [15:0] ey; reg [7:0] ep;
    string fn;
    initial begin
        if (!$value$plusargs("VEC=%s", fn)) fn = "sim/results/fp16/unit/epi_vec.hex";
        f = $fopen(fn, "r");
        if (f == 0) begin $display("FAIL: cannot open %s", fn); $finish; end
        repeat (2) @(negedge clk); rst_n = 1;
        while (!$feof(f)) begin
            r = $fscanf(f, "%h %d %h %h\n", acc, m, ey, ep);
            if (r != 4) break;
            mode = m[0];
            @(negedge clk); go = 1; @(negedge clk); go = 0;
            lat = 1;
            while (!done) begin @(negedge clk); lat = lat + 1; end
            n = n + 1;
            if (y !== ey || (mode && pix !== ep) || lat != (mode ? 10 : 1)) begin
                bad = bad + 1;
                if (bad <= 10) $display("MISMATCH acc=%h mode=%0d y=%h(exp %h) pix=%h(exp %h) lat=%0d",
                                        acc, mode, y, ey, pix, ep, lat);
            end
        end
        if (bad == 0 && n > 0) $display("PASS: fp16_epi_tb %0d vectors bit-exact", n);
        else                   $display("FAIL: fp16_epi_tb %0d/%0d mismatches", bad, n);
        $finish;
    end
endmodule
