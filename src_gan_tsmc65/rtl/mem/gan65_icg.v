`timescale 1ns / 1ps

// ============================================================================
// gan65_icg -- integrated clock gate, gclk = clk & en_latched (enable latched
// while clk is low, glitch-free positive-edge gate).
// Behavioural model, used by all RTL simulations (non-blocking updates so
// posedge samplers never race). Synthesis replaces this file with a
// site-specific wrapper (same module name and ports) that instantiates the
// library ICG cell; the cell name never appears in this tree.
// ============================================================================
module gan65_icg (
    input  wire clk,
    input  wire en,
    output wire gclk
);
    reg en_l;
    always @(clk or en)
        if (!clk) en_l <= en;
    assign gclk = clk & en_l;
endmodule
