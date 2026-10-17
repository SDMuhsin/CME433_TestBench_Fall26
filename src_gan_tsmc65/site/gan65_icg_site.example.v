`timescale 1ns / 1ps

// Template: copy to site/gan65_icg_site.v (git-ignored) and map gan65_icg to the
// library's integrated clock-gating cell (latch-based, positive-edge, test enable tied 0).
module gan65_icg (
    input  wire clk,
    input  wire en,
    output wire gclk
);
    <ICG_CELL> u_cg (.<CLK_PIN>(clk), .<EN_PIN>(en), .<TE_PIN>(1'b0), .<GCLK_PIN>(gclk));
endmodule
