`timescale 1ns / 1ps

// cssm -- signed static segmented multiplier with error correction (C-SSM), reproduced from
//   A. G. M. Strollo, E. Napoli, D. De Caro, N. Petra, G. Saggese, G. Di Meo,
//   "Approximate Multipliers Using Static Segmentation: Error Analysis and Improvements",
//   IEEE Trans. Circuits Syst. I, vol. 69, no. 6, pp. 2449-2462, Jun. 2022,
//   doi:10.1109/TCSI.2022.3152921  (Sec. IV: signed SSM, eq. (15)-(17); correction eq. (20)).
//
// n = 8 operands, segment width m (default 6, a configuration of the paper's Table III).
// Each operand X is split (paper Fig. 6) into
//   alpha_X = X[n-1:m-1]            n-m+1 bits; all-0 or all-1 <=> X fits in m signed bits
//   L_X     = X[m-1:0]              m-bit signed (equals X when alpha_X is all-0 / all-1)
//   H_X     = X[n-1:n-m]            m-bit signed, weight 2^(n-m)
// and replaced by (eq. (15)):  X ~ L_X               if alpha_X in {0, -1}
//                              X ~ H_X * 2^(n-m)     otherwise.
// Error correction (eq. (20)): the LSB of H_X becomes X[n-m] | X[n-m-1] (halves the mean
// truncation error of the dropped bits eps_X = X[n-m-1:0]).
// The product (eq. (17)) uses one signed m x m inner multiplier and a left shift of
// 0, n-m or 2(n-m) bits.  Exact whenever both operands fit in m signed bits.
//
// Configuration: `define CSSM_M (segment width, 2 < m < 8) and `define CSSM_CORR (1 = eq. (20)
// correction, 0 = plain SSM, eq. (15)) on the tool command line; defaults m = 6, corrected.
// Ports and semantics follow src_int8/rtl/int/mq_mul8.v (combinational, signed 8 x 8 -> 16).
`ifndef CSSM_M
`define CSSM_M 6
`endif
`ifndef CSSM_CORR
`define CSSM_CORR 1
`endif

// One operand: segment select (alpha test, L / H mux, correction) -> m-bit signed value + flag
module cssm_seg #(parameter N = 8, parameter M = 6, parameter CORR = 1) (
    input  wire [N-1:0] x,
    output wire [M-1:0] v,      // L_X or (corrected) H_X, m-bit signed
    output wire         hi      // 1: H_X selected (operand scaled by 2^(n-m))
);
    localparam S = N - M;
    wire [S:0] alpha = x[N-1:M-1];
    assign hi = ~(&alpha | ~|alpha);
    wire [M-1:0] h = (CORR != 0) ? {x[N-1:S+1], x[S] | x[S-1]} : x[N-1:S];
    assign v = hi ? h : x[M-1:0];
endmodule

module mq_mul8 (
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] p
);
    localparam N = 8, M = `CSSM_M, S = N - M;

    wire [M-1:0] va, vb;
    wire         ha, hb;
    cssm_seg #(.N(N), .M(M), .CORR(`CSSM_CORR)) u_sa (.x(a), .v(va), .hi(ha));
    cssm_seg #(.N(N), .M(M), .CORR(`CSSM_CORR)) u_sb (.x(b), .v(vb), .hi(hb));

    // signed m x m inner multiplier
    wire signed [2*M-1:0] q = $signed(va) * $signed(vb);
    wire signed [15:0]    qx = q;                           // sign-extended to 16 bits

    // output shifter: 2^(S*(ha+hb)); |result| <= 2^(2n-2), fits 16 bits
    assign p = (ha & hb) ? (qx <<< (2 * S)) : ((ha | hb) ? (qx <<< S) : qx);
endmodule
