// Second top level for the gate-level run of gan65_bench_tb: records the switching activity
// of the netlist (gan65_bench_tb.dut) for the first image as SAIF, when +SAIF=<file> is given.
// Window: from the first START command (after reset and the CSR writes) to the end of the
// STATUS check, i.e. START, the stream (283,984 elements) and the whole generator compute; only
// the 784-pixel read-back (<1 % of the clocks) is outside.
module gls_saif;
    string  saif;
    longint c0;
    initial begin
        if ($value$plusargs("SAIF=%s", saif)) begin
            $set_gate_level_monitoring("on");
            $set_toggle_region(gan65_bench_tb.dut);
            wait (gan65_bench_tb.fd != 0);
            @(negedge gan65_bench_tb.clk);
            c0 = gan65_bench_tb.cyc;
            $toggle_start;
            $display("SAIF window open at %0t, clk %0d", $time, c0);
            wait (gan65_bench_tb.half == 4);       // RD_HALF: pixel read-back begins
            $toggle_stop;
            $toggle_report(saif, 1.0e-12, "gan65_bench_tb.dut");
            $display("SAIF window closed at %0t, %0d clk -> %s", $time, gan65_bench_tb.cyc - c0, saif);
        end
    end
endmodule
