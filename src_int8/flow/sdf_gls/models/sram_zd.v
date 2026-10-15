`timescale 1ns / 1ps
// sram_zd.v -- zero-delay SRAM model for the NOSDF reference run of run_sdf_gls.sh (power: glitch-free
// activity).  = the behavioural model src/rtl/mem/gf180_sram_macro.v (used by the zero-delay GLS
// src_int8/flow/gls/run_gls.sh) with the per-bit masked write written as one word-wide masked write:
// CVC drops a non-blocking assignment to a bit-select of a memory word (`mem[A][i] <= D[i]` leaves
// the word X; Icarus is fine), and the vendor model sram_sdf.v samples A/D 100 ps after CLK, which
// needs real delays.  Same function: active-low CEN / GWEN / per-bit WEN, Q registered on enabled
// cycles (also on writes, with the old word, as the behavioural model).
module gf180mcu_ocd_ip_sram__sram256x8m8wm1 (
`ifdef USE_POWER_PINS
    inout        VDD,
    inout        VSS,
`endif
    input        CLK,
    input        CEN,
    input  [7:0] A,
    input        GWEN,
    input  [7:0] WEN,
    input  [7:0] D,
    output [7:0] Q
);
    reg [7:0] mem [0:255];
    reg [7:0] q_reg;

    assign Q = q_reg;

    always @(posedge CLK) begin
        if (!CEN) begin
            if (!GWEN)
                mem[A] <= (mem[A] & WEN) | (D & ~WEN);
            q_reg <= mem[A];
        end
    end
endmodule
