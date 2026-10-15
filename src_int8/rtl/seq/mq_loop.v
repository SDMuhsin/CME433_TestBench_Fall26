`timescale 1ns / 1ps

// ============================================================================
// mq_loop -- microcode program counter with two zero-overhead hardware loops
// (copied from the FP16 chip).
//
//   jump          pc <- entry (START / state reset)
//   adv           the current uop completes:
//     LOOPl n     counter l <- 0, limit <- n - 1 (count field), body start <- pc + 1
//     eol[0]      end of a level-0 body: loop back while k != limit0 (k++)
//     eol[1]      end of a level-1 body: loop back while d != limit1 (d++)
//                 (level 0 is checked first, so both may end on one uop)
//     otherwise   pc <- pc + 1
// k (level 0) and d (level 1) feed the address generator.
// ============================================================================
module mq_loop #(
    parameter integer PCW = 8
) (
    input  wire           clk,
    input  wire           rst_n,
    input  wire           jump,
    input  wire [PCW-1:0] entry,
    input  wire           adv,
    input  wire           ld0,
    input  wire           ld1,
    input  wire [7:0]     count,
    input  wire [1:0]     eol,
    output reg  [PCW-1:0] pc,
    output reg  [7:0]     k,
    output reg  [7:0]     d
);
    reg [7:0]     lim0, lim1;
    reg [PCW-1:0] start0, start1;
    wire back0 = eol[0] && (k != lim0);
    wire back1 = eol[1] && (d != lim1) && !back0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= {PCW{1'b0}}; k <= 8'd0; d <= 8'd0;
            lim0 <= 8'd0; lim1 <= 8'd0; start0 <= {PCW{1'b0}}; start1 <= {PCW{1'b0}};
        end else if (jump) begin
            pc <= entry;
        end else if (adv) begin
            if (ld0) begin k <= 8'd0; lim0 <= count; start0 <= pc + 1'b1; end
            if (ld1) begin d <= 8'd0; lim1 <= count; start1 <= pc + 1'b1; end
            if (back0) begin
                k  <= k + 8'd1;
                pc <= start0;
            end else if (back1) begin
                d  <= d + 8'd1;
                pc <= start1;
            end else begin
                pc <= pc + 1'b1;
            end
        end
    end
endmodule
