`timescale 1ns / 1ps

// ============================================================================
// mq_sat -- sat_w(v): clamp a WI-bit signed value to the signed w-bit range,
// w selected by `ww` (0: 8, 1: 16, 2: 24, 3: raw 32 = low 32 bits), and return
// it sign-extended to 32 bits (spec section 4.2).  Combinational.
// ============================================================================
module mq_sat #(
    parameter integer WI = 50
) (
    input  wire signed [WI-1:0] v,
    input  wire        [1:0]    ww,
    output reg  signed [31:0]   y
);
    wire neg = v[WI-1];
    // in range for width w iff bits [WI-1 : w-1] are all equal to the sign
    wire in8  = (&v[WI-1:7])  | ~(|v[WI-1:7]);
    wire in16 = (&v[WI-1:15]) | ~(|v[WI-1:15]);
    wire in24 = (&v[WI-1:23]) | ~(|v[WI-1:23]);

    always @* begin
        case (ww)
            2'd0:    y = in8  ? {{24{v[7]}},  v[7:0]}  : (neg ? -32'sd128     : 32'sd127);
            2'd1:    y = in16 ? {{16{v[15]}}, v[15:0]} : (neg ? -32'sd32768   : 32'sd32767);
            2'd2:    y = in24 ? {{8{v[23]}},  v[23:0]} : (neg ? -32'sd8388608 : 32'sd8388607);
            default: y = v[31:0];
        endcase
    end
endmodule
