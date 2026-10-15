`timescale 1ns / 1ps

// ============================================================================
// mb_lane -- the FP16 x FP16 -> FP32 MAC lane with FP16 writeback (spec
// section 3).  Every arithmetic op of the Mamba token step is a sequence of
// lane steps on this one accumulator:
//
//   step:  acc <- RNE32(base + a*b)     base = first ? fp32(init) : acc
//   out:   y    = wb(acc, scale)        (combinational from acc)
//
// `first` starts a new accumulation in the same issue, so no separate load
// cycle is needed: init = 16'h0000 starts from +0, otherwise from the exact
// FP16 init (bias / residual / constant).  Op shapes (see rtl_units.md):
//   GEMV row  first+init, then K-1 plain steps            y = wb(acc, s)
//   MUL       one first step, init 0                      y = wb(a*b)
//   MADD2     first step (init 0 or cb), one more step    scan / conv
//   LERP      two steps with NLU operands, scale = NLU scale
//
// Pipeline (issue in cycle 0, acc valid in cycle 3, `done` high in cycle 3):
//   S1  mb_fp16_mul(a, b) -> p_r; init -> fp32 -> base_r     (edge 1)
//   S2  mb_fp32_add_align(first_r ? base_r : acc, p_r)       (edge 2)
//   S3  mb_fp32_add_norm -> acc                              (edge 3)
// S2 reads the acc that S3 writes, so issues must be >= 2 cycles apart
// (`can_issue` = !issue).  a, b, init must come from registers or the NLU.
// `clear` drops in-flight steps.  Datapath registers have no reset.
// ============================================================================
module mb_lane (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              clear,
    input  wire              issue,
    input  wire              first,
    input  wire [15:0]       a,
    input  wire [15:0]       b,
    input  wire [15:0]       init,
    input  wire signed [7:0] scale,
    output wire              can_issue,
    output wire              idle,
    output reg               done,
    output reg  [31:0]       acc,
    output wire [15:0]       y
);
    reg        v1, v2, first_r;
    reg [31:0] p_r, base_r;
    reg [23:0] al_ml;
    reg [26:0] al_ms;
    reg [7:0]  al_el;
    reg        al_sl, al_sub, al_zl;

    assign can_issue = !issue;
    assign idle      = !(issue | v1 | v2);

    // S1
    wire [31:0] p, init32;
    mb_fp16_mul     u_mul  (.a(a), .b(b), .p(p));
    mb_fp16_to_fp32 u_init (.h(init), .f(init32));

    // S2
    wire [23:0] ml;
    wire [26:0] ms;
    wire [7:0]  el;
    wire        sl, sb, zl;
    mb_fp32_add_align u_al (.x(first_r ? base_r : acc), .y(p_r), .m_l(ml), .m_s(ms),
                            .e_l(el), .s_l(sl), .sub(sb), .z_l(zl));

    // S3
    wire [31:0] s;
    mb_fp32_add_norm u_nm (.m_l(al_ml), .m_s(al_ms), .e_l(al_el), .s_l(al_sl),
                           .sub(al_sub), .z_l(al_zl), .s(s));

    // writeback
    mb_fp32_wb u_wb (.acc(acc), .scale(scale), .y(y));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1 <= 1'b0; v2 <= 1'b0; done <= 1'b0;
        end else if (clear) begin
            v1 <= 1'b0; v2 <= 1'b0; done <= 1'b0;
        end else begin
            v1   <= issue;
            v2   <= v1;
            done <= v2;
        end
    end

    always @(posedge clk) begin
        if (issue) begin
            p_r     <= p;
            base_r  <= init32;
            first_r <= first;
        end
        if (v1) begin
            al_ml <= ml; al_ms <= ms; al_el <= el;
            al_sl <= sl; al_sub <= sb; al_zl <= zl;
        end
        if (v2 && !clear) acc <= s;
    end
endmodule
