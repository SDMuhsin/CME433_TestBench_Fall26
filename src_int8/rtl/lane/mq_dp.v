`timescale 1ns / 1ps

// ============================================================================
// mq_dp -- the arithmetic datapath: one 24 x 17 multiplier shared by the MAC
// lane (mq_lane, spec 4.1) and the writeback (mq_wb, spec 4.2).
//
// The multiplier computes a * b in every cycle the lane issues; in all other
// cycles it belongs to the writeback, which needs it only once the lane is
// idle (the sequencer reads Y no earlier than 3 cycles after the lane went
// idle and issues nothing meanwhile).  Y latency from the last MAC's issue:
// lane 2 stages + writeback 3 stages = y valid in cycle 5, as with the
// original 3 + 2 arrangement, so the microcode timing is unchanged.
// ============================================================================
module mq_dp (
    input  wire        clk,
    input  wire        rst_n,
    // lane
    input  wire        clear,
    input  wire        issue,
    input  wire        first,
    input  wire [23:0] a,
    input  wire [15:0] b,
    input  wire [31:0] init,
    input  wire [3:0]  ps,
    output wire        idle,
    output wire        done,
    output wire [31:0] acc,
    // writeback
    input  wire [1:0]  wb_mode,
    input  wire [4:0]  wb_sh,
    input  wire [15:0] wb_rq_m,
    input  wire [5:0]  wb_rq_s,
    input  wire [15:0] wb_addend,
    input  wire [1:0]  wb_ww,
    input  wire [1:0]  wb_ph,
    output wire [31:0] y
);
    wire [23:0] ma;
    wire [16:0] mb;
    wire signed [40:0] p;

    mq_mul24x17 u_mul (
        .a(issue ? a : ma),
        .b(issue ? {b[15], b} : mb),
        .p(p));

    mq_lane u_lane (
        .clk(clk), .rst_n(rst_n), .clear(clear), .issue(issue), .first(first),
        .p(p[39:0]), .init(init), .ps(ps), .idle(idle), .done(done), .acc(acc));

    mq_wb u_wb (
        .clk(clk), .acc(acc), .mode(wb_mode), .sh(wb_sh), .rq_m(wb_rq_m), .rq_s(wb_rq_s),
        .addend(wb_addend), .ww(wb_ww), .ph(wb_ph), .ma(ma), .mb(mb), .p(p), .y(y));
endmodule
