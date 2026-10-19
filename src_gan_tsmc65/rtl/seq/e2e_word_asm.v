`timescale 1ns / 1ps

// ============================================================================
// e2e_word_asm -- little-endian byte -> word assembly of the host stream for
// a DATA_W = 8*NB bit datapath.  Every stream element (latent, bias, weight)
// is NB bytes, least significant first; `take` consumes one byte.  `last` is
// high while the byte being taken completes a word, and `word` is then that
// word ({byte_in, earlier bytes}).  NB = 1 (8-bit chip): pure wires, last = 1.
// `clr` (START / soft reset) returns to the first byte of a word.
// ============================================================================
module e2e_word_asm #(
    parameter integer NB = 1
) (
    input  wire            clk,
    input  wire            rst_n,
    input  wire            clr,
    input  wire            take,
    input  wire [7:0]      byte_in,
    output wire            last,
    output wire [8*NB-1:0] word
);
    generate
        if (NB == 1) begin : G_BYTE
            assign last = 1'b1;
            assign word = byte_in;
            wire _unused = &{1'b0, clk, rst_n, clr, take};
        end else begin : G_WORD
            localparam integer PH_W = $clog2(NB);
            localparam [PH_W-1:0] PH_LAST = NB - 1;
            reg [PH_W-1:0]     ph;            // byte index within the word
            reg [8*NB-9:0]     lo;            // bytes 0 .. NB-2 of the word
            integer i;
            assign last = (ph == PH_LAST);
            assign word = {byte_in, lo};
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n)              ph <= {PH_W{1'b0}};
                else if (clr)            ph <= {PH_W{1'b0}};
                else if (take)           ph <= last ? {PH_W{1'b0}} : ph + 1'b1;
            end
            always @(posedge clk) begin
                if (take && !last) begin
                    for (i = 0; i < NB - 2; i = i + 1) lo[8*i +: 8] <= lo[8*(i+1) +: 8];
                    lo[8*(NB-2) +: 8] <= byte_in;
                end
            end
        end
    endgenerate
endmodule
