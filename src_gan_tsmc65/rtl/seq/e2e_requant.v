`timescale 1ns / 1ps

// ============================================================================
// e2e_requant -- per-neuron bias + requantize + activation for dla_e2e_chip.
//
// Bit-exact implementation of the G300 integer epilogue (golden/model.py),
// D = DATA_W (8 | 16), S = REQ_S (16 for the 8-bit chip, cfg/w<D>):
//
//   t   = acc*M_a + bias*M_b + 2^(S-1)          (signed)
//   pre = t >>> S                               (floor)
//   ReLU mode : q = clamp(pre, 0, 2^(D-1)-1)    (8-bit chip: == the reference's
//                                                 "t<0 -> 0, else min((t+2^15)>>16,127)")
//   Tanh mode : pre = clamp(pre, -2^22, 2^22); idx = (pre + 2^22) >> 8  (0..32768)
//               pu  = largest v in 0..255 with T[v] <= idx (8-step binary
//                     search over e2e_tanh_rom), q = pu - 128 = pu ^ 8'h80,
//                     sign-extended to D bits (the pixel is 8-bit at every width)
//
// Datapath: one LSB-first shift-right multiplier with a 34-bit adder
// (multiplicand M unsigned 32 b, multiplier operand signed; the MSB partial
// product is subtracted).  bias*M_b runs first (D iterations) and is parked in
// the tb register, then acc*M_a (ACC_W iterations, hi preloaded with the
// 2^(S-1) rounding constant), then one (ACC_W+34)-bit add, one saturate/clamp
// cycle and, in tanh mode, 8 ROM-search cycles.  Latency start->valid:
// D + ACC_W + 3 clk (ReLU; 35 for the 8-bit chip), +8 in tanh mode.
// `start` is ignored while busy; `clear` aborts.
//
// Area note: acc, bias, m_a and m_b are NOT latched -- the caller must hold
// them stable from `start` until `valid` (e2e_seq does: acc is the C-bank read
// register, bias the inactive half of the bias double buffer, m_* the CSRs
// selected by the tile's layer).  Datapath registers have no reset.
// ============================================================================
module e2e_requant #(
    parameter integer DATA_W = 8,
    parameter integer ACC_W  = 24,
    parameter integer REQ_S  = 16
) (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,     // synchronous abort -> idle
    input  wire                     start,
    input  wire                     mode_tanh,
    input  wire signed [ACC_W-1:0]  acc,
    input  wire signed [DATA_W-1:0] bias,
    input  wire        [31:0]       m_a,
    input  wire        [31:0]       m_b,
    output wire                     busy,
    output reg                      valid,
    output reg         [DATA_W-1:0] q
);
    localparam integer HI_W  = 34;                    // 32-bit multiplicand + sign + carry
    localparam integer F_W   = HI_W + ACC_W;          // {hi, lo} = acc*M_a + 2^(S-1)
    localparam integer BP_W  = HI_W + DATA_W;         // bias*M_b
    localparam integer PRE_W = F_W - REQ_S;           // t >>> S
    localparam integer TB_W  = (BP_W > PRE_W) ? BP_W : PRE_W;
    localparam integer CNT_W = $clog2(ACC_W);
    localparam [CNT_W-1:0] LAST_B = DATA_W - 1;
    localparam [CNT_W-1:0] LAST_A = ACC_W - 1;
    localparam signed [TB_W-1:0] QMAX = (1 << (DATA_W - 1)) - 1;
    localparam [HI_W-1:0]        RND  = {{(HI_W-1){1'b0}}, 1'b1} << (REQ_S - 1);

    localparam [2:0] S_IDLE = 3'd0,
                     S_MULB = 3'd1,
                     S_MULA = 3'd2,
                     S_ADD  = 3'd3,
                     S_SAT  = 3'd4,
                     S_TANH = 3'd5;

    reg [2:0]              state;
    reg [CNT_W-1:0]        cnt;
    reg                    tanh_q;
    reg signed [HI_W-1:0]  hi;
    reg        [ACC_W-1:0] lo;
    reg signed [TB_W-1:0]  tb;       // bias product, later the rounded pre-activation
    reg        [15:0]      idx;
    reg        [7:0]       v, vbit;

    // ---- shared 34-bit add/sub step of the shift-right multiplier ----
    wire        in_b    = (state == S_MULB);
    wire [31:0] m_cur   = in_b ? m_b : m_a;
    wire        last_it = in_b ? (cnt == LAST_B) : (cnt == LAST_A);
    wire signed [HI_W-1:0] m_ext = {2'b00, m_cur};
    wire signed [HI_W-1:0] sum   = !lo[0]   ? hi
                                 : last_it  ? (hi - m_ext)
                                 :            (hi + m_ext);
    wire signed [ACC_W-1:0] bias_ext = bias;          // sign-extended multiplier operand
    // bias*M_b = {hi', lo'[ACC_W-1 -: DATA_W]} after the DATA_W-th shift
    wire signed [BP_W-1:0]  b_prod = {(sum >>> 1), sum[0], lo[ACC_W-1:ACC_W-DATA_W+1]};

    // ---- final add: {hi,lo} = acc*M_a + 2^(S-1), tb = bias*M_b ----
    wire signed [F_W-1:0] f_a    = {hi, lo};
    wire signed [F_W-1:0] tb_ext = tb;
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [F_W-1:0] t_full = f_a + tb_ext;            // only [F_W-1:S] used
    wire signed [PRE_W-1:0] t_pre = t_full[F_W-1:REQ_S];    // pre = (t + 2^(S-1)) >>> S

    // ---- activation ----
    localparam signed [TB_W-1:0] TMAX = 4194304;     // 4.0 in Q20 = 2^22
    wire signed [TB_W-1:0] pre = tb;
    wire signed [TB_W-1:0] pre_c = (pre > TMAX) ? TMAX : (pre < -TMAX) ? -TMAX : pre;
    wire        [TB_W-1:0] idx_full = pre_c + TMAX;  // 0 .. 2^23, only [23:8] used
    /* verilator lint_on UNUSEDSIGNAL */
    wire [DATA_W-1:0] relu_q = pre[TB_W-1] ? {DATA_W{1'b0}}
                             : (pre > QMAX) ? QMAX[DATA_W-1:0] : {1'b0, pre[DATA_W-2:0]};

    // ---- tanh threshold ROM + binary search ----
    wire [7:0]  v_try = v | vbit;
    wire [14:0] t_try;
    e2e_tanh_rom u_rom (.v(v_try), .t(t_try));
    wire        take = ({1'b0, t_try} <= idx);
    wire signed [7:0]        pix_s   = (take ? v_try : v) ^ 8'h80;
    wire signed [DATA_W-1:0] pix_ext = pix_s;        // int8 pixel, sign-extended

    assign busy = (state != S_IDLE);

    // ---- control (reset) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            cnt    <= {CNT_W{1'b0}};
            tanh_q <= 1'b0;
            valid  <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (clear) state <= S_IDLE;
            else case (state)
                S_IDLE: if (start) begin
                    tanh_q <= mode_tanh;
                    cnt    <= {CNT_W{1'b0}};
                    state  <= S_MULB;
                end
                S_MULB: begin
                    cnt <= last_it ? {CNT_W{1'b0}} : cnt + 1'b1;
                    if (last_it) state <= S_MULA;
                end
                S_MULA: begin
                    cnt <= cnt + 1'b1;
                    if (last_it) state <= S_ADD;
                end
                S_ADD:  state <= S_SAT;
                S_SAT: begin
                    if (tanh_q) state <= S_TANH;
                    else begin
                        valid <= 1'b1;
                        state <= S_IDLE;
                    end
                end
                S_TANH: if (vbit[0]) begin
                    valid <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end

    // ---- datapath (no reset) ----
    always @(posedge clk) begin
        case (state)
            S_IDLE: if (start) begin
                hi <= {HI_W{1'b0}};
                lo <= bias_ext;
            end
            S_MULB: begin
                if (last_it) begin
                    tb <= b_prod;
                    hi <= RND;                        // + 2^(S-1) rounding constant
                    lo <= acc;
                end else begin
                    hi <= sum >>> 1;
                    lo <= {sum[0], lo[ACC_W-1:1]};
                end
            end
            S_MULA: begin
                hi <= sum >>> 1;
                lo <= {sum[0], lo[ACC_W-1:1]};
            end
            S_ADD: tb <= t_pre;
            S_SAT: begin
                if (tanh_q) begin
                    idx  <= idx_full[23:8];
                    v    <= 8'd0;
                    vbit <= 8'h80;
                end else begin
                    q    <= relu_q;
                end
            end
            S_TANH: begin
                if (take) v <= v_try;
                vbit <= vbit >> 1;
                if (vbit[0]) q <= pix_ext;
            end
            default: ;
        endcase
    end

endmodule
