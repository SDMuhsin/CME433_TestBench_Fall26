// Second top level for the gate-level run of tb_mq_chip: records switching activity of the
// netlist (tb_mq_chip.dut) for one token as SAIF.  Window = run_token(GLS_TOK) of the TB:
// START, the 54,280-byte stream, compute, STATUS and the 256-byte logit read-back (opens when
// the TB's token index becomes GLS_TOK, closes when the TB books that token's cycles).
//   +SAIF=<file> (default mq_chip.saif)  +GLS_TOK=<n> (default 1)
module gls_saif;
    string  saif;
    integer tok;
    longint c0;
    initial begin
        if (!$value$plusargs("SAIF=%s", saif)) saif = "mq_chip.saif";
        if (!$value$plusargs("GLS_TOK=%d", tok)) tok = 1;
        $set_gate_level_monitoring("on");
        $set_toggle_region(tb_mq_chip.dut);
        wait (tb_mq_chip.t == tok);
        @(posedge tb_mq_chip.clk);
        c0 = tb_mq_chip.cyc;
        $toggle_start;
        $display("SAIF window open: token %0d at %0t, clk %0d", tok, $time, c0);
        @(tb_mq_chip.loop_cycles);
        $toggle_stop;
        $toggle_report(saif, 1.0e-12, "tb_mq_chip.dut");
        $display("SAIF window closed: token %0d at %0t, %0d clk -> %s", tok, $time, tb_mq_chip.cyc - c0, saif);
    end
endmodule
