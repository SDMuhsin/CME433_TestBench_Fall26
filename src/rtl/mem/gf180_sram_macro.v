`timescale 1ns / 1ps

// ============================================================================
// gf180mcu_ocd_ip_sram__sram256x8m8wm1 -- the SRAM macro as synthesis black
// box (`SYNTHESIS) or behavioural simulation model (copied from
// rtl/gf180_sram_1rw_256x8.v).  LibreLane links the real LEF/GDS/LIB.
// Model: active-low CEN / GWEN / per-bit WEN, Q registered on enabled cycles.
// ============================================================================
`ifdef SYNTHESIS
(* blackbox *)
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
endmodule
`else
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
    integer i;

    assign Q = q_reg;

    always @(posedge CLK) begin
        if (!CEN) begin
            if (!GWEN) begin
                for (i = 0; i < 8; i = i + 1)
                    if (!WEN[i]) mem[A][i] <= D[i];
            end
            q_reg <= mem[A];
        end
    end
endmodule
`endif
