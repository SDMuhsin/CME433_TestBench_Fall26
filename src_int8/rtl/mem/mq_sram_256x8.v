`timescale 1ns / 1ps

// ============================================================================
// mq_sram_256x8 -- wrapper of one GF180MCU OCD 256x8 1RW SRAM macro
// (gf180mcu_ocd_ip_sram__sram256x8m8wm1) with a chip enable so idle macros do
// not toggle.  Read data is valid one clock after an enabled cycle and holds
// while disabled.  Power pins are left unconnected in RTL and joined by
// PDN_MACRO_CONNECTIONS (".*u_sram.*").
// ============================================================================
module mq_sram_256x8 (
    input  wire       clk,
    input  wire       ce,
    input  wire       we,
    input  wire [7:0] addr,
    input  wire [7:0] wdata,
    output wire [7:0] rdata
);
    gf180mcu_ocd_ip_sram__sram256x8m8wm1 u_sram (
        .CLK  (clk),
        .CEN  (~ce),
        .A    (addr),
        .GWEN (~we),
        .WEN  (we ? 8'h00 : 8'hFF),
        .D    (wdata),
        .Q    (rdata)
    );
endmodule
