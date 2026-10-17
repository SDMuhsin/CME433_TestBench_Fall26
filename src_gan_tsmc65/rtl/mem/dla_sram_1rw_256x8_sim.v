`timescale 1ns / 1ps

// ============================================================================
// dla_sram_1rw_256x8 (fast simulation model) -- same module name, ports and
// cycle behaviour as mem/dla_sram_1rw_256x8.v (latch RF, ce = 1): registered
// read of addr on every clock, read-before-write, write visible to the read of
// the next clock.  Plain flip-flop array, used by the Verilator benchmark only
// because 2,048 per-word clock gates make the latch RF slow to simulate.
// Equivalence with the latch RF: bench/check_mem.sh (unit, random) and
// bench/run_bench.sh --latch-rf (full chip).  Not for synthesis.
// ============================================================================
module dla_sram_1rw_256x8 (
    input  wire       clk,
    input  wire       we,
    input  wire [7:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata
);
    reg [7:0] mem [0:255];
    reg [7:0] q_r;
    always @(posedge clk) begin
        if (we) mem[addr] <= wdata;
        q_r <= mem[addr];
    end
    assign rdata = q_r;
endmodule
