`timescale 1ns / 1ps

// e2e_tanh_rom_tb -- EXHAUSTIVE check of the tanh path of e2e_requant
// (clamp -> idx -> 256x15 threshold ROM binary search -> pixel) over every LUT
// index 0..32768 against the reference formula evaluated on the Q20 tanh LUT
// (tb/data/g300_fp/g300_tanh_lut_fp.memh, read here in the TB only):
//     pix = clamp(((LUT[idx] + 2^20)*255 + 2^20) >> 21, 0, 255) - 128
// The unit is driven with M_a = 2^16, M_b = 0 so pre = acc exactly; acc is
// idx*256 - 2^22 plus a random 0..255 offset (the dropped LSBs of the idx shift).
// Also checks pre beyond the +/-2^22 clamp.  Run from repo root.
module e2e_tanh_rom_tb;
    localparam int LUT_SIZE = 32769;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg         start = 0;
    reg  signed [23:0] acc = 0;
    wire        busy, valid;
    wire [7:0]  q;

    e2e_requant dut (.clk(clk), .rst_n(rst_n), .clear(1'b0), .start(start), .mode_tanh(1'b1),
                     .acc(acc), .bias(8'sd0), .m_a(32'h0001_0000), .m_b(32'd0),
                     .busy(busy), .valid(valid), .q(q));

    reg signed [23:0] lut [0:LUT_SIZE-1];
    integer idx, errs, n, seed;
    reg signed [63:0] p;
    reg [7:0] expv;

    function automatic [7:0] ref_pix(input integer ix);
        reg signed [63:0] t;
        begin
            t = ((64'sd0 + lut[ix] + (64'sd1 <<< 20)) * 255 + (64'sd1 <<< 20)) >>> 21;
            if (t < 0) t = 0;
            if (t > 255) t = 255;
            ref_pix = t[7:0] ^ 8'h80;
        end
    endfunction

    task automatic run_one(input signed [23:0] a, input [7:0] e);
        begin
            acc = a;
            start <= 1'b1; @(posedge clk); start <= 1'b0;
            while (!valid) @(posedge clk);
            n = n + 1;
            if (q !== e) begin
                errs = errs + 1;
                if (errs <= 10) $display("MISMATCH acc=%0d : got %02x exp %02x", a, q, e);
            end
            @(posedge clk);
        end
    endtask

    initial begin
        $readmemh("tb/data/g300_fp/g300_tanh_lut_fp.memh", lut);
        errs = 0; n = 0; seed = 7;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        for (idx = 0; idx < LUT_SIZE; idx = idx + 1) begin
            p = idx * 256 - (1 << 22) + ((idx == LUT_SIZE-1) ? 0 : ($urandom(seed) % 256));
            seed = seed + 1;
            run_one(p[23:0], ref_pix(idx));
        end
        // beyond the clamp
        run_one(24'sd4194305, ref_pix(LUT_SIZE-1));
        run_one(24'sd8388607, ref_pix(LUT_SIZE-1));
        run_one(-24'sd4194305, ref_pix(0));
        run_one(-24'sd8388608, ref_pix(0));
        if (errs == 0) $display("PASS: e2e_tanh_rom exhaustive %0d/%0d (all 32769 LUT indices + clamp) bit-exact", n, n);
        else           $display("FAIL: e2e_tanh_rom %0d/%0d mismatches", errs, n);
        $finish;
    end
endmodule
