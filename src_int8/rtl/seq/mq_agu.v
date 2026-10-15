`timescale 1ns / 1ps

// ============================================================================
// mq_agu -- address generator: addr = base + k_off + d_off, with
//   am[1:0]: 0 none, 1 +k, 2 +2k        (level-0 counter, INT8 / INT16 arrays)
//   am[3:2]: 0 none, 1 +d, 2 +2d, 3 +4d (level-1 counter; 4d = H entry of channel d)
// 12-bit internal address (HMEM entry or BMEM byte, spec section 6).  Combinational.
// ============================================================================
module mq_agu (
    input  wire [11:0] base,
    input  wire [3:0]  am,
    input  wire [7:0]  k,
    input  wire [7:0]  d,
    output wire [11:0] addr
);
    reg [11:0] off_k, off_d;
    always @* begin
        case (am[1:0])
            2'd1:    off_k = {4'd0, k};
            2'd2:    off_k = {3'd0, k, 1'b0};
            default: off_k = 12'd0;
        endcase
        case (am[3:2])
            2'd1:    off_d = {4'd0, d};
            2'd2:    off_d = {3'd0, d, 1'b0};
            2'd3:    off_d = {2'd0, d, 2'b00};
            default: off_d = 12'd0;
        endcase
    end

    assign addr = base + off_k + off_d;
endmodule
