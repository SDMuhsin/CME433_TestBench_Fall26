`timescale 1ns / 1ps

// ============================================================================
// mq_wb -- lane writeback (spec section 4.2), three register stages on the
// multiplier it borrows from mq_dp while the lane is idle:
//
//   wb_sh(acc, sh)    = rsh(acc, sh)                        mode SH / SHA
//   wb_rq(acc, M, s)  = (acc * M + 2^(s-1)) >> s            mode RQ / RQA
//   v   = wb_x(acc) + (mode A ? addend : 0)
//   y   = sat_w(v), w by ww (8 / 16 / 24 / raw 32), sign-extended to 32 b
//
// Both forms are one rsh of a 48-bit product: prod = acc * Me, Me = M (RQ) or
// 1 (SH), shift k = s or sh.  The 32 x 16 product is built in two passes of
// the 24 x 17 multiplier, phased by `ph` from the sequencer (its Y-wait
// counter, 0 while the lane is still busy):
//   ph 0 (edge 1): hi   <- acc[31:16] (signed) * Me            32 b
//   ph 1 (edge 2): prod <- (hi << 16) + acc[15:0] (unsigned) * Me   48 b exact
//   ph 2 (edge 3): y    <- sat_w((prod >>> k) + prod[k-1] + addend)
// The round bit prod[k-1] comes out of the shifter (mq_rsh) and enters the
// addend adder as a carry, so there is no rounding adder.  acc, Me, k, mode,
// addend and ww must be stable from the ph 0 cycle to the one in which y is
// read (ph 3); the sequencer guarantees this by holding the uop that reads Y
// in P0 (its fields and the RQ register do not change) with the lane idle.
// All arithmetic is exact: v has 49 bits before saturation.
// ============================================================================
module mq_wb (
    input  wire        clk,
    input  wire [31:0] acc,
    input  wire [1:0]  mode,         // 0 SH, 1 RQ, 2 SHA, 3 RQA
    input  wire [4:0]  sh,
    input  wire [15:0] rq_m,
    input  wire [5:0]  rq_s,
    input  wire [15:0] addend,
    input  wire [1:0]  ww,
    input  wire [1:0]  ph,           // multiplier pass / stage (sequencer ycnt)
    output wire [23:0] ma,           // multiplier operands while the lane is idle
    output wire [16:0] mb,
    input  wire [40:0] p,            // their product (mq_dp)
    output reg  [31:0] y
);
    // ---- multiplier operands: the two halves of acc times Me
    wire [15:0] me = mode[0] ? rq_m : 16'd1;
    wire [5:0]  k  = mode[0] ? rq_s : {1'b0, sh};
    assign ma = (ph == 2'd0) ? {{8{acc[31]}}, acc[31:16]} : {8'd0, acc[15:0]};
    assign mb = {1'b0, me};

    // ---- ph 0: high half; ph 1: full product
    reg signed [31:0] hi;
    reg signed [47:0] prod;
    always @(posedge clk) begin
        if (ph == 2'd0) hi   <= p[31:0];
        if (ph == 2'd1) prod <= {hi, 16'd0} + {15'd0, p[32:0]};
    end

    // ---- ph 2: shift, round, addend, saturate
    wire [47:0] q;
    wire        rbit;
    mq_rsh #(.WI(48), .WO(48), .KW(6)) u_rsh (.v(prod), .k(k), .q(q), .rbit(rbit));

    wire signed [48:0] v = $signed({q[47], q}) + $signed({{33{addend[15] & mode[1]}}, addend & {16{mode[1]}}})
                         + $signed({48'd0, rbit});

    wire signed [31:0] y_c;
    mq_sat #(.WI(49)) u_sat (.v(v), .ww(ww), .y(y_c));

    always @(posedge clk) y <= y_c;
endmodule
