`timescale 1ns / 1ps

// ilm -- improved logarithmic multiplier (ILM-0: exact adders), reproduced from
//   M. S. Ansari, B. F. Cockburn, J. Han, "An Improved Logarithmic Multiplier for
//   Energy-Efficient Neural Computing", IEEE Trans. Computers, vol. 70, no. 4, pp. 614-625,
//   Apr. 2021, doi:10.1109/TC.2020.2992113  (same design: M. S. Ansari, PhD thesis,
//   University of Alberta, 2019, Sec. 5.2, Algorithm 2, Fig. 5.3).
//
// Unsigned n = 8 core (eq. (5.5)-(5.7)): each operand X = 2^k + q, with 2^k the nearest power
// of two found by the nearest-one detector (NOD: up-rounding stage T, then a leading-one
// detector; ties round up; no up-rounding beyond 2^(n-1), as in the paper). The product is
//   A * B ~ 2^(k1+k2) + q1 2^k2 + q2 2^k1          (q1 q2 dropped: double-sided error).
// Signed INT8 (the paper maps NN weights to sign + magnitude): |a| x |b| through the core,
// product negated when the signs differ, 0 when an operand is 0.
// Ports and semantics follow src_int8/rtl/int/mq_mul8.v (combinational, signed 8 x 8 -> 16).
// Reference model: src_int8/approx/ref/ilm.py (bit-exact).

// Nearest-one detector + priority encoder: x (> 0) -> exponent k of the nearest power of two
module ilm_nod #(parameter N = 8, parameter KW = 3) (
    input  wire [N-1:0]  x,
    output reg  [KW-1:0] k
);
    // up-rounding stage (Fig. 5.3(c)): T[i+1] = 1 when X[i] and X[i-1] are both 1
    wire [N-1:0] t;
    assign t[0] = x[0];
    assign t[1] = x[1];
    genvar i;
    generate
        for (i = 2; i < N; i = i + 1) begin : g_up
            assign t[i] = x[i] | (x[i-1] & x[i-2]);
        end
    endgenerate
    // leading-one detector + encoder on T
    integer j;
    always @* begin
        k = 0;
        for (j = 1; j < N; j = j + 1)
            if (t[j]) k = j;
    end
endmodule

// Unsigned ILM core: a, b > 0 -> approximate product (2N-bit)
module ilm_core #(parameter N = 8, parameter KW = 3) (
    input  wire [N-1:0]   a,
    input  wire [N-1:0]   b,
    output wire [2*N-1:0] p
);
    wire [KW-1:0] k1, k2;
    ilm_nod #(.N(N), .KW(KW)) u_na (.x(a), .k(k1));
    ilm_nod #(.N(N), .KW(KW)) u_nb (.x(b), .k(k2));
    // residues q = X - 2^k (two's complement, |q| < 2^(N-1))
    wire signed [N+1:0] q1 = $signed({2'b00, a}) - $signed({{(N+1){1'b0}}, 1'b1} << k1);
    wire signed [N+1:0] q2 = $signed({2'b00, b}) - $signed({{(N+1){1'b0}}, 1'b1} << k2);
    wire signed [2*N+1:0] t1 = $signed(q1) <<< k2;                    // q1 2^k2
    wire signed [2*N+1:0] t2 = $signed(q2) <<< k1;                    // q2 2^k1
    wire [KW:0]           ks = k1 + k2;                               // k1 + k2 (KW+1 bits)
    wire        [2*N+1:0] d  = {{(2*N+1){1'b0}}, 1'b1} << ks;         // DEC(k1 + k2), one-hot
    wire signed [2*N+1:0] s  = $signed(d) + t1 + t2;
    assign p = s[2*N-1:0];
endmodule

module mq_mul8 (
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] p
);
    // sign-magnitude conversion (|-128| = 128 fits 8 unsigned bits)
    wire [7:0] ma = a[7] ? -a : a;
    wire [7:0] mb = b[7] ? -b : b;
    wire [15:0] m;
    ilm_core #(.N(8), .KW(3)) u_core (.a(ma), .b(mb), .p(m));
    wire zero = ~|a | ~|b;
    assign p = zero ? 16'sd0 : ((a[7] ^ b[7]) ? -$signed(m) : $signed(m));
endmodule
