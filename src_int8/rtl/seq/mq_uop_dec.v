`timescale 1ns / 1ps

// ============================================================================
// mq_uop_dec -- splits a micro-op into its fields (layout: mq_ucode_defs.vh,
// generated from src_int8/ucode/isa.py) and derives the resource flags used
// by the P0 stall check: source A is read by MAC / INIT / MOV / NLD, source B
// by MAC only.
//   use_s  consumes sw stream bytes       use_m  reads memory in P0
//   use_y  reads the lane writeback (waits for lane + mq_wb to drain)
// ============================================================================
module mq_uop_dec (
    input  wire [52:0] uop,
    output wire [2:0]  op,
    output wire [1:0]  eol,
    output wire [2:0]  sa,
    output wire [2:0]  ra,
    output wire [2:0]  sb,
    output wire [2:0]  rb,
    output wire        wr,
    output wire        wm,
    output wire [1:0]  sw,
    output wire [1:0]  mw,
    output wire [3:0]  ps,
    output wire [1:0]  wmode,
    output wire [4:0]  sh,
    output wire [1:0]  ww,
    output wire        nstep,
    output wire [11:0] base,
    output wire [3:0]  am,
    output wire        use_s,
    output wire        use_m,
    output wire        use_y
);
`include "mq_ucode_defs.vh"

    assign op    = uop[F_OP +: 3];
    assign eol   = uop[F_EOL +: 2];
    assign sa    = uop[F_SA +: 3];
    assign ra    = uop[F_RA +: 3];
    assign sb    = uop[F_SB +: 3];
    assign rb    = uop[F_RB +: 3];
    assign wr    = uop[F_WR];
    assign wm    = uop[F_WM];
    assign sw    = uop[F_SW +: 2];
    assign mw    = uop[F_MW +: 2];
    assign ps    = uop[F_PS +: 4];
    assign wmode = uop[F_WMODE +: 2];
    assign sh    = uop[F_SH +: 5];
    assign ww    = uop[F_WW +: 2];
    assign nstep = uop[F_NSTEP];
    assign base  = uop[F_BASE +: 12];
    assign am    = uop[F_AM +: 4];

    wire has_a = (op == OP_MAC) || (op == OP_INIT) || (op == OP_MOV) || (op == OP_NLD);
    wire has_b = (op == OP_MAC);

    assign use_s = (has_a && sa == SRC_S) || (has_b && sb == SRC_S);
    assign use_m = (has_a && sa == SRC_M) || (has_b && sb == SRC_M);
    assign use_y = (has_a && sa == SRC_Y);
endmodule
