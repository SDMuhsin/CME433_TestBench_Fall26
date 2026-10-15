`timescale 1ns / 1ps

// ============================================================================
// mq_lane -- the INT24 x INT16 -> INT32 MAC lane (spec section 4.1).  Every
// arithmetic op of the token step is a sequence of lane steps on this one
// accumulator:
//
//   step:  acc <- base + rsh(a * b, ps)     base = first ? init : acc
//
// `first` starts a new accumulation in the same issue (init = 0 or 16, the
// RMSNorm eps; any 32-bit value is accepted).  No saturation: the spec proves
// |acc| < 2^31 for every accumulation of section 5.2.
//
// The multiplier is not in here: mq_dp owns the one 24 x 17 multiplier and
// feeds its product `p` (a * b while `issue` is high; the writeback borrows it
// otherwise).  Pipeline (issue in cycle 0, acc valid and `done` high in
// cycle 2):
//   S1  p_r <- p = a * b (40 b), ps / first registered                (edge 1)
//   S2  acc <- base + (p_r >>> ps_r) + round bit                       (edge 2)
// rsh is a truncating shift plus its round bit as the adder's carry-in
// (mq_rsh), so there is no rounding adder.  Issues must be >= 2 cycles apart
// (the sequencer's two-phase rule); a, b, ps come from registers or the NLU;
// `init` is read in S2, i.e. it must be stable for the cycle after an issue
// with `first` (the sequencer's INIT uop updates it >= 2 cycles after the
// preceding MAC's P1, and the MAC in flight does not use it).  `clear` drops
// in-flight steps.  The writeback (mq_wb) reads `acc` once `idle` is high.
// ============================================================================
module mq_lane (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,
    input  wire        issue,
    input  wire        first,
    input  wire [39:0] p,            // a * b from mq_dp's multiplier, valid while issue
    input  wire [31:0] init,
    input  wire [3:0]  ps,
    output wire        idle,
    output reg         done,
    output reg  [31:0] acc
);
    reg        v1, first1;
    reg [39:0] p_r;
    reg [3:0]  ps_r;

    assign idle = !(issue | v1);

    wire [31:0] q;
    wire        rbit;
    mq_rsh #(.WI(40), .WO(32), .KW(4)) u_rsh (.v(p_r), .k(ps_r), .q(q), .rbit(rbit));

    wire [31:0] base = first1 ? init : acc;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1 <= 1'b0; done <= 1'b0;
        end else if (clear) begin
            v1 <= 1'b0; done <= 1'b0;
        end else begin
            v1   <= issue;
            done <= v1;
        end
    end

    // datapath registers (no reset)
    always @(posedge clk) begin
        if (issue) begin
            p_r <= p; ps_r <= ps; first1 <= first;
        end
        if (v1 && !clear) acc <= base + q + {31'd0, rbit};
    end
endmodule
