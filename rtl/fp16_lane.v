`timescale 1ns / 1ps

// ============================================================================
// fp16_lane -- the single FP16 MAC lane of dla_fp16_chip.
//
//   acc <- fp32(bias)                                   (ld_bias, exact)
//   acc <- RNE32(acc + w*x)  for each issued (w, x)    (in issue order)
//
// `issue`, `w`, `x` come straight from registers in fp16_seq (they are the
// operand registers).  Pipeline (issue high in cycle 0 -> acc updated 3 edges later):
//   S1 : fp16_mul(w, x) -> exact FP32 product p_r      (edge 1, v1)
//   S2 : fp32_add_align(acc, p_r) -> al_*              (edge 2, v2)
//   S3 : fp32_add_norm -> acc                          (edge 3)
// S2 reads acc, which S3 writes, so the issue interval must be >= 2 clk
// (`can_issue` = !issue; fp16_seq needs two FIFO pops per weight anyway).
// ld_bias is only legal while `idle` (the caller also
// guarantees the previous acc has been consumed).  The FP16 bias is
// canonicalised like fp16_mul's operands (FTZ / saturate).
// Datapath registers have no reset (only the valid bits do).
// ============================================================================
module fp16_lane (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,        // drop in-flight operations (START / soft reset)
    input  wire        issue,
    input  wire [15:0] w,
    input  wire [15:0] x,
    input  wire        ld_bias,
    input  wire [15:0] bias,
    output wire        can_issue,
    output wire        idle,
    output reg  [31:0] acc
);
    reg        v1, v2;
    reg [31:0] p_r;
    reg [23:0] al_ml;
    reg [26:0] al_ms;
    reg [7:0]  al_el;
    reg        al_sl, al_sub, al_zl;

    assign can_issue = !issue;
    assign idle      = !(issue | v1 | v2);

    // S1
    wire [31:0] p;
    fp16_mul u_mul (.a(w), .b(x), .p(p));

    // S2
    wire [23:0] ml;
    wire [26:0] ms;
    wire [7:0]  el;
    wire        sl, sb, zl;
    fp32_add_align u_al (.x(acc), .y(p_r), .m_l(ml), .m_s(ms), .e_l(el), .s_l(sl), .sub(sb), .z_l(zl));

    // S3
    wire [31:0] s;
    fp32_add_norm u_nm (.m_l(al_ml), .m_s(al_ms), .e_l(al_el), .s_l(al_sl), .sub(al_sub), .z_l(al_zl), .s(s));

    // bias FP16 -> FP32 (exact): exp + 112, fraction << 13
    wire        b_z   = (bias[14:10] == 5'd0);
    wire        b_sat = (bias[14:10] == 5'd31);
    wire [7:0]  b_e   = b_sat ? 8'd142 : ({3'b000, bias[14:10]} + 8'd112);
    wire [9:0]  b_m   = b_sat ? 10'h3FF : bias[9:0];
    wire [31:0] b32   = b_z ? 32'h0000_0000 : {bias[15], b_e, b_m, 13'd0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1 <= 1'b0; v2 <= 1'b0;
        end else if (clear) begin
            v1 <= 1'b0; v2 <= 1'b0;
        end else begin
            v1 <= issue;
            v2 <= v1;
        end
    end

    always @(posedge clk) begin
        if (issue) p_r <= p;
        if (v1) begin
            al_ml <= ml; al_ms <= ms; al_el <= el;
            al_sl <= sl; al_sub <= sb; al_zl <= zl;
        end
        if (ld_bias)              acc <= b32;
        else if (v2 && !clear)    acc <= s;
    end
endmodule
