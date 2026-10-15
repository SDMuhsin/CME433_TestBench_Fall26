`timescale 1ns / 1ps

// ============================================================================
// mb_regfile -- 8 x FP16 scalar registers of the sequencer (R0..R7):
// two combinational read ports, one write port.  No reset (written before read).
// ============================================================================
module mb_regfile (
    input  wire        clk,
    input  wire        we,
    input  wire [2:0]  wa,
    input  wire [15:0] wd,
    input  wire [2:0]  ra,
    input  wire [2:0]  rb,
    output wire [15:0] qa,
    output wire [15:0] qb
);
    reg [15:0] r [0:7];

    always @(posedge clk) begin
        if (we) r[wa] <= wd;
    end

    assign qa = r[ra];
    assign qb = r[rb];
endmodule
