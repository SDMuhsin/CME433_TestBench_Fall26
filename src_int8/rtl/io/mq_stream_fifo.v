`timescale 1ns / 1ps

// ============================================================================
// mq_stream_fifo -- weight-stream byte FIFO with 1 / 2 / 3-byte little-endian
// pops (adapted from the FP16 chip's word FIFO).
//
// Bytes are accepted while `arm` (token step in flight) up to TOTAL per token;
// a byte arriving when the FIFO is full or after TOTAL sets the sticky
// err_ovf.  word = {head + 2, head + 1, head} (LE; the upper bytes are only
// meaningful when held); `cnt` lets the sequencer check that pop_n bytes are
// present; pop removes pop_n (1..3) bytes.  `room` (count <= DEPTH - 3) is the
// host flow-control term of HRDY: the host checks HRDY before every byte and
// at most two more bytes can be in flight behind that check.  `clr` empties
// the FIFO and clears the byte count and err_ovf (START / STATE_RESET / soft
// reset).
// ============================================================================
module mq_stream_fifo #(
    parameter integer DEPTH = 16,                 // bytes, power of 2
    parameter integer AW    = 4,                  // log2(DEPTH)
    parameter integer TOTAL = 54280               // bytes per token
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clr,
    input  wire        arm,
    input  wire [7:0]  st_byte,
    input  wire        st_valid,
    input  wire        pop,
    input  wire [1:0]  pop_n,
    output wire [23:0] word,
    output wire [AW:0] cnt,
    output wire        room,
    output wire        all_rcvd,
    output reg  [19:0] byte_cnt,
    output reg         err_ovf
);
    localparam [AW:0]  FULL  = DEPTH, ROOM_MAX = DEPTH - 3;
    localparam [19:0]  LAST  = TOTAL;

    reg [7:0]    mem [0:DEPTH-1];
    reg [AW-1:0] wp, rp;
    reg [AW:0]   count;

    wire full = (count == FULL);
    wire take = st_valid && arm;
    wire push = take && !all_rcvd && !(full && !pop);
    wire [AW-1:0] rp1 = rp + {{(AW-1){1'b0}}, 1'b1};
    wire [AW-1:0] rp2 = rp + {{(AW-2){1'b0}}, 2'd2};

    assign all_rcvd = (byte_cnt == LAST);
    assign word     = {mem[rp2], mem[rp1], mem[rp]};
    assign cnt      = count;
    assign room     = (count <= ROOM_MAX);

    always @(posedge clk) begin
        if (push) mem[wp] <= st_byte;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wp <= {AW{1'b0}}; rp <= {AW{1'b0}}; count <= {(AW+1){1'b0}};
            byte_cnt <= 20'd0; err_ovf <= 1'b0;
        end else if (clr) begin
            wp <= {AW{1'b0}}; rp <= {AW{1'b0}}; count <= {(AW+1){1'b0}};
            byte_cnt <= 20'd0; err_ovf <= 1'b0;
        end else begin
            if (push) begin
                wp       <= wp + 1'b1;
                byte_cnt <= byte_cnt + 20'd1;
            end
            if (take && !push) err_ovf <= 1'b1;
            if (pop) rp <= rp + {{(AW-2){1'b0}}, pop_n};
            count <= count + {{AW{1'b0}}, push} - (pop ? {{(AW-1){1'b0}}, pop_n} : {(AW+1){1'b0}});
        end
    end
endmodule
