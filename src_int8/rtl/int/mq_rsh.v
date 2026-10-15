`timescale 1ns / 1ps

// ============================================================================
// mq_rsh -- the one rounding primitive of mq_chip (spec section 2):
//   rsh(v, k) = (v + 2^(k-1)) >> k   (arithmetic), rsh(v, 0) = v
// Round half up, ties towards +inf.  Delivered as a truncating shift plus a
// round bit, so the caller adds it as the carry-in of an adder it has anyway:
//   rsh(v, k) = (v >>> k) + v[k-1]        (bit k-1 of v; 0 for k = 0)
// which holds for any signed v because (v mod 2^k) >= 2^(k-1) iff v[k-1].  The
// shift is done on {v, 0} so the round bit falls out of the shifter.  WI-bit
// signed input, KW-bit shift, quotient truncated to WO bits (the caller
// guarantees that rsh(v, k) fits).  Combinational.
// ============================================================================
module mq_rsh #(
    parameter integer WI = 40,
    parameter integer WO = 32,
    parameter integer KW = 4
) (
    input  wire signed [WI-1:0] v,
    input  wire        [KW-1:0] k,
    output wire        [WO-1:0] q,       // v >>> k, low WO bits
    output wire                 rbit     // v[k-1] (0 for k = 0); rsh(v, k) = q + rbit
);
    wire signed [WI:0] t = $signed({v, 1'b0}) >>> k;
    assign q    = t[WO:1];
    assign rbit = t[0];
endmodule
