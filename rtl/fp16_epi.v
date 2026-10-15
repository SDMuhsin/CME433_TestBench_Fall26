`timescale 1ns / 1ps

// ============================================================================
// fp16_epi -- per-neuron epilogue of dla_fp16_chip.
//
// On `go` (acc stable): y = fp16(acc)
//     |acc| < 2^-14 (exp < 113)  -> +0          (flush-to-zero BEFORE rounding)
//     else RNE to 10 fraction bits; rounded magnitude > 65504 -> +-65504 (saturate)
//   ReLU mode : y = sign ? +0 : y                             -> done 1 clk later
//   tanh mode : pixel = #{ v in 1..255 : key(y) >= T[v] }    -> done 9 clk later
//     key = sign ? ~y : y | 0x8000 (monotone ordered key); 8-step binary search
//     (MSB first) over fp16_tanh_rom.  T is ascending, so the result is the
//     largest v with T[v] <= key (0 if none).
// Outputs y / pix hold until the next go.  `busy` is high from go to done.
// ============================================================================
module fp16_epi (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,
    input  wire        go,
    input  wire        tanh_mode,
    input  wire [31:0] acc,
    output reg  [15:0] y,
    output reg  [7:0]  pix,
    output wire        busy,
    output reg         done
);
    // ---- FP32 -> FP16 ----
    wire [7:0]  e    = acc[30:23];
    wire        tiny = (e < 8'd113);
    wire        up   = acc[12] & ((|acc[11:0]) | acc[13]);
    wire [10:0] mr   = {1'b0, acc[22:13]} + {10'd0, up};
    wire [8:0]  e16  = {1'b0, e} - 9'd112 + {8'd0, mr[10]};
    wire        ovf  = (e16 > 9'd30);
    wire [15:0] h    = tiny ? 16'h0000 :
                       ovf  ? {acc[31], 15'h7BFF} :
                              {acc[31], e16[4:0], mr[9:0]};

    // ---- threshold search ----
    reg  [15:0] key;
    reg  [7:0]  lo;
    reg  [2:0]  n;
    reg         srch;
    wire [7:0]  cand = lo | (8'h80 >> n);
    wire [15:0] thr;
    fp16_tanh_rom u_rom (.a(cand), .t(thr));
    wire        ge   = (key >= thr);

    reg         done_pend;
    assign busy = srch | done_pend;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            srch <= 1'b0; done <= 1'b0; done_pend <= 1'b0; n <= 3'd0;
        end else if (clear) begin
            srch <= 1'b0; done <= 1'b0; done_pend <= 1'b0; n <= 3'd0;
        end else begin
            done      <= 1'b0;
            done_pend <= 1'b0;
            if (go) begin
                n <= 3'd0;
                if (tanh_mode) srch <= 1'b1;
                else begin done <= 1'b1; end
            end else if (srch) begin
                n <= n + 3'd1;
                if (n == 3'd7) begin
                    srch      <= 1'b0;
                    done_pend <= 1'b1;
                end
            end
            if (done_pend) done <= 1'b1;
        end
    end

    always @(posedge clk) begin
        if (go) begin
            y   <= (h[15] && !tanh_mode) ? 16'h0000 : h;
            key <= h[15] ? ~h : {1'b1, h[14:0]};
            lo  <= 8'd0;
        end else if (srch) begin
            if (ge) lo <= cand;
        end
        if (done_pend) pix <= lo;
    end
endmodule
