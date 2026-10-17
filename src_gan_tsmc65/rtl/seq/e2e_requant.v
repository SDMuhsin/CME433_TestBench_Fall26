`timescale 1ns / 1ps

// ============================================================================
// e2e_requant -- per-neuron bias + requantize + activation for dla_e2e_chip.
//
// Bit-exact implementation of the G300 integer epilogue (g300_pipeline_top
// S_REQ, scripts/gen_g300_int8_assets.py), S = 16:
//
//   t   = acc*M_a + bias*M_b + 2^15            (signed, <= 58 b)
//   pre = t >>> 16                             (floor, 42 b)
//   ReLU mode : q = clamp(pre, 0, 127)          (== the reference's "t<0 -> 0,
//                                                 else min((t+2^15)>>16,127)")
//   Tanh mode : pre = clamp(pre, -2^22, 2^22); idx = (pre + 2^22) >> 8  (0..32768)
//               pu  = largest v in 0..255 with T[v] <= idx (8-step binary
//                     search over e2e_tanh_rom), q = pu - 128 = pu ^ 8'h80
//
// Datapath: one LSB-first shift-right multiplier with a 34-bit adder
// (multiplicand M unsigned 32 b, multiplier operand signed; the MSB partial
// product is subtracted).  bias*M_b runs first (8 iterations) and is parked in
// a 42-bit register, then acc*M_a (24 iterations, hi preloaded with the 2^15
// rounding constant), then one 58-bit add, one saturate/clamp cycle and, in
// tanh mode, 8 ROM-search cycles.  Latency start->valid: 35 clk (ReLU),
// 43 clk (tanh).  `start` is ignored while busy; `clear` aborts.
//
// Area note: acc, bias, m_a and m_b are NOT latched -- the caller must hold
// them stable from `start` until `valid` (e2e_seq does: acc is the C-bank read
// register, bias the inactive half of the bias double buffer, m_* the CSRs
// selected by the tile's layer).  Datapath registers have no reset.
// ============================================================================
module e2e_requant (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clear,     // synchronous abort -> idle
    input  wire               start,
    input  wire               mode_tanh,
    input  wire signed [23:0] acc,
    input  wire signed [7:0]  bias,
    input  wire        [31:0] m_a,
    input  wire        [31:0] m_b,
    output wire               busy,
    output reg                valid,
    output reg         [7:0]  q
);
    localparam [2:0] S_IDLE = 3'd0,
                     S_MULB = 3'd1,
                     S_MULA = 3'd2,
                     S_ADD  = 3'd3,
                     S_SAT  = 3'd4,
                     S_TANH = 3'd5;

    reg [2:0]         state;
    reg [4:0]         cnt;
    reg               tanh_q;
    reg signed [33:0] hi;
    reg        [23:0] lo;
    reg signed [41:0] tb;       // bias product, later the rounded pre-activation
    reg        [15:0] idx;
    reg        [7:0]  v, vbit;

    // ---- shared 34-bit add/sub step of the shift-right multiplier ----
    wire        in_b    = (state == S_MULB);
    wire [31:0] m_cur   = in_b ? m_b : m_a;
    wire        last_it = in_b ? (cnt == 5'd7) : (cnt == 5'd23);
    wire signed [33:0] m_ext = {2'b00, m_cur};
    wire signed [33:0] sum   = !lo[0]   ? hi
                             : last_it  ? (hi - m_ext)
                             :            (hi + m_ext);

    // ---- 58-bit final add: {hi,lo} = acc*M_a + 2^15, tb = bias*M_b ----
    wire signed [57:0] f_a  = {hi, lo};
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [57:0] t_full = f_a + {{16{tb[41]}}, tb};   // only [57:16] used

    // ---- activation ----
    localparam signed [41:0] TMAX = 42'sd4194304;    // 4.0 in Q20 = 2^22
    wire signed [41:0] pre = tb;
    wire signed [41:0] pre_c = (pre > TMAX) ? TMAX : (pre < -TMAX) ? -TMAX : pre;
    wire        [41:0] idx_full = pre_c + TMAX;      // 0 .. 2^23, only [23:8] used
    /* verilator lint_on UNUSEDSIGNAL */
    wire        [7:0]  relu_q = pre[41] ? 8'd0 : ((pre > 42'sd127) ? 8'd127 : {1'b0, pre[6:0]});

    // ---- tanh threshold ROM + binary search ----
    wire [7:0]  v_try = v | vbit;
    wire [14:0] t_try;
    e2e_tanh_rom u_rom (.v(v_try), .t(t_try));
    wire        take = ({1'b0, t_try} <= idx);

    assign busy = (state != S_IDLE);

    // ---- control (reset) ----
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;
            cnt    <= 5'd0;
            tanh_q <= 1'b0;
            valid  <= 1'b0;
        end else begin
            valid <= 1'b0;
            if (clear) state <= S_IDLE;
            else case (state)
                S_IDLE: if (start) begin
                    tanh_q <= mode_tanh;
                    cnt    <= 5'd0;
                    state  <= S_MULB;
                end
                S_MULB: begin
                    cnt <= last_it ? 5'd0 : cnt + 5'd1;
                    if (last_it) state <= S_MULA;
                end
                S_MULA: begin
                    cnt <= cnt + 5'd1;
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
                hi <= 34'sd0;
                lo <= {{16{bias[7]}}, bias};
            end
            S_MULB: begin
                if (last_it) begin
                    // bias*M_b = {hi', lo'[23:16]} after the 8th shift
                    tb <= {(sum >>> 1), sum[0], lo[23:17]};
                    hi <= 34'sd32768;                 // + 2^15 rounding constant
                    lo <= acc;
                end else begin
                    hi <= sum >>> 1;
                    lo <= {sum[0], lo[23:1]};
                end
            end
            S_MULA: begin
                hi <= sum >>> 1;
                lo <= {sum[0], lo[23:1]};
            end
            S_ADD: tb <= t_full[57:16];               // pre = (t + 2^15) >>> 16
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
                if (vbit[0]) q <= (take ? v_try : v) ^ 8'h80;
            end
            default: ;
        endcase
    end

endmodule
