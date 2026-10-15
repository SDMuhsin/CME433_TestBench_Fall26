`timescale 1ns / 1ps

// ============================================================================
// mq65_icg -- integrated clock gate, gclk = clk & en_latched (enable latched
// while clk is low, glitch-free positive-edge gate).
// Behavioural model, used by all RTL simulations (non-blocking updates so
// posedge samplers never race). Synthesis / LEC replace this file with the
// site-specific wrapper that maps mq65_icg to the library ICG cell
// (::MQ65_ICG_RTL in site/site.tcl, template site/mq65_icg_site.example.v).
// ============================================================================
module mq65_icg (
    input  wire clk,
    input  wire en,
    output wire gclk
);
    reg en_l;
    always @(clk or en)
        if (!clk) en_l <= en;
    assign gclk = clk & en_l;
endmodule
