`timescale 1ns / 1ps

// ============================================================================
// mb_nlu_frac -- interpolation weight q / 2^11 -> FP16 (combinational, exact).
//
// q in 0..2048 has at most 11 significant bits, so the FP16 value is exact.
// q = 0 -> +0; otherwise leading one at bit p gives exponent p - 11 (biased
// p + 4) and the bits below it as the fraction.
// ============================================================================
module mb_nlu_frac (
    input  wire [11:0] q,
    output wire [15:0] h
);
    reg [3:0] p;
    integer k;
    always @* begin
        p = 4'd0;
        for (k = 0; k < 12; k = k + 1)
            if (q[k]) p = k[3:0];
    end

    wire [11:0] n = q << (4'd11 - p);                            // leading one at bit 11

    assign h = (q == 12'd0) ? 16'h0000 : {1'b0, {1'b0, p} + 5'd4, n[10:1]};
endmodule
