`timescale 1ns / 1ps

// ============================================================================
// tb_rf_vs_sram -- lock-step check of the 65 nm latch RF (mq65_latch_rf)
// against the GF180 SRAM behavioural model used by the src_int8 sims
// (gf180mcu_ocd_ip_sram__sram256x8m8wm1, wired as src_int8 mq_sram_256x8).
// Random ce / we / addr / wdata (phases with a 4-word address window to force
// write-then-read and same-cycle read/write collisions); rdata compared with
// 4-state equality every cycle.  +N=<cycles> (default 200000).
// ============================================================================
module tb_rf_vs_sram;
    reg        clk = 1'b0;
    reg        ce = 1'b0, we = 1'b0;
    reg  [7:0] addr = 8'h00, wdata = 8'h00;
    wire [7:0] q_ref, q_rf;
    integer    n, cyc, errs, nrd, nwr;

    always #20 clk = ~clk;       // 40 ns clock, as the chip

    gf180mcu_ocd_ip_sram__sram256x8m8wm1 u_ref (
        .CLK(clk), .CEN(~ce), .A(addr), .GWEN(~we), .WEN(we ? 8'h00 : 8'hFF),
        .D(wdata), .Q(q_ref));
    mq65_latch_rf #(.WIDTH(8), .AW(8)) u_dut (
        .clk(clk), .ce(ce), .we(we), .addr(addr), .wdata(wdata), .rdata(q_rf));

    initial begin
        if (!$value$plusargs("N=%d", n)) n = 200000;
        errs = 0; nrd = 0; nwr = 0;
        // fill every word once so later reads compare real data, not X
        for (cyc = 0; cyc < 256; cyc = cyc + 1) begin
            @(negedge clk); ce = 1; we = 1; addr = cyc[7:0]; wdata = $random;
        end
        for (cyc = 0; cyc < n; cyc = cyc + 1) begin
            @(negedge clk);
            if (q_rf !== q_ref) begin
                errs = errs + 1;
                if (errs <= 10) $display("MISMATCH cyc %0d: rf %h ref %h", cyc, q_rf, q_ref);
            end
            ce    = ($random % 8) != 0;
            we    = ($random % 3) == 0;
            addr  = ((cyc / 5000) % 2) ? ($random & 8'h03) : $random;
            wdata = $random;
            if (ce && we) nwr = nwr + 1; else if (ce) nrd = nrd + 1;
        end
        @(negedge clk);
        if (q_rf !== q_ref) errs = errs + 1;
        $display("cycles %0d writes %0d reads %0d mismatches %0d", n, nwr, nrd, errs);
        if (errs == 0) $display("PASS rf_vs_sram"); else $display("FAIL rf_vs_sram");
        $finish;
    end
endmodule
