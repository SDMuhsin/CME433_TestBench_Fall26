`timescale 1ns/1ps
// Model self-test for the SDF GLS (run.sh): the CVC behaviours the generated cell models and the
// SRAM model depend on, each found broken once while bringing the flow up.
//   1. CLK->Q of a flop with an SDF INTERCONNECT (MIPD) on CLK = MIPD + IOPATH  (MIPD bypass)
//   2. SRAM read through MIPDs on every A bit and CLK: right word, Q at CLK + MIPD + IOPATH
//   3. edge-specific SETUP limits: posedge-D and negedge-D checks get different values
//      (cvc_sdf.patch fix 1; a 0.20 ns posedge-D setup and 0.10 ns negedge-D setup are annotated,
//      the D rise 0.15 ns before CLK must violate, the D fall 0.15 ns before CLK must not)
//   4. negative HOLD limit read as negative (clamped to 0), not as +0.30 (cvc_sdf.patch fix 2):
//      a D change 0.05 ns after CLK must not violate
module tb_selftest;
    reg clk0 = 0, d = 0, cen = 1, gwen = 1;
    reg [7:0] a = 0, sd = 0, wen = 8'hff;
    wire clk, q1, q2;
    wire [7:0] sq;
    integer err = 0;
    real t_clk;
    gf180mcu_as_sc_mcu7t3v3__clkbuff_4 cb (.A(clk0), .Y(clk));
    gf180mcu_as_sc_mcu7t3v3__dfxtp_2 f1 (.CLK(clk), .D(d), .Q(q1));
    gf180mcu_as_sc_mcu7t3v3__dfsrtp_2 f2 (.CLK(clk), .D(d), .RN(1'b1), .SN(1'b1), .Q(q2));
    gf180mcu_ocd_ip_sram__sram256x8m8wm1 m (.CLK(clk), .CEN(cen), .GWEN(gwen), .WEN(wen), .A(a), .D(sd), .Q(sq));
    initial begin
        $sdf_annotate("selftest.sdf", tb_selftest);
        // 1. flop CLK->Q: clk0 rises at 20 -> clk 20.2 -> CLK pins 20.25 -> Q 20.25 + 0.448
        #10 d = 1;
        #10 clk0 = 1; t_clk = $realtime;
        @(q1); if ($realtime - t_clk < 0.69 || $realtime - t_clk > 0.71) begin err = err + 1; $display("FAIL 1: dfxtp CLK->Q %0.3f ns", $realtime - t_clk); end
        #20 clk0 = 0;
        // 2. SRAM: write 0x5a at address 0x25, read it back
        #5 cen = 0; gwen = 0; wen = 8'h00; a = 8'h25; sd = 8'h5a;
        #15 clk0 = 1; #20 clk0 = 0;
        #5 gwen = 1; wen = 8'hff; a = 8'h01; #2 a = 8'h25;
        #13 clk0 = 1; t_clk = $realtime;
        @(sq); t_clk = $realtime - t_clk;           // first Q bit: Q[1], annotated 6.78 ns
        #1 if (sq !== 8'h5a || t_clk < 7.10 || t_clk > 7.12) begin err = err + 1; $display("FAIL 2: SRAM read %h, first Q change %0.3f ns", sq, t_clk); end
        #20 clk0 = 0; cen = 1;
        // 3. D rise 0.15 ns before the f1 CLK pin edge (= clk0 + 0.25): setup posedge-D 0.20 -> violation
        d = 0;
        #20 clk0 = 1; #0.10 d = 1; #19.9 clk0 = 0;
        //    D fall 0.15 ns before the edge: setup negedge-D 0.10 -> no violation
        #20 clk0 = 1; #0.10 d = 0;
        // 4. D rise 0.05 ns after the CLK pin edge: hold -0.30 (clamped to 0) -> no violation
        #0.20 d = 1; #19.7 clk0 = 0; #20;
        $display("SELFTEST %s (%0d errors)", err ? "FAIL" : "DONE", err);
        $finish;
    end
endmodule
