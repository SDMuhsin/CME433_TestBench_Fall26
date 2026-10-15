`timescale 1ns / 1ps

// ============================================================================
// tb_mb_abort -- abort / reset path test of mb_chip (spec section 7.1).
//
// The TB is the external host on the 11 pad terminals, as in tb_mb_chip.  It
// aborts the chip in every way the host can (soft reset, STATE_RESET and START
// while busy, rst_n, CS_N deassertion mid-frame, stream overrun) at many points
// of a token step -- directed offsets in every stream section, triggers on
// sequencer activity (NLU ops, lane in flight, logit / state writes) and
// seeded random offsets -- and after each abort checks:
//   * STATUS / CTRL / byte count / ID values, the host link and sequencer FSMs
//     idle (hierarchical), no hang (bounded waits, watchdog);
//   * the expected state (spec 7.1): the on-chip SSM / conv state read back
//     over RD_MEM_Q equals golden (zero after STATE_RESET, unchanged if the
//     abort preserves it), and the next tokens' logits and state are
//     bit-exact vs src/golden;
//   * no X / Z on any chip output after the first reset (iverilog), no IO
//     contention, IO drivers off while rst_n is low.
// Vectors: python3 -m src.tb.abort.gen_vectors (+VEC=<dir>).  +SEED=<n>
// (random part), +NRAND=<n> random scenarios (default 40).  Prints one line
// per scenario, a coverage table of where the aborts landed, and PASS / FAIL.
// ============================================================================
module tb_mb_abort;
    localparam int WORDS  = 49920;              // stream words per token
    localparam int TBYTES = 2 * WORDS;
    localparam int VOCAB  = 128;
    localparam int SWORDS = 960;                // state words H0 H1 CONV0 CONV1 = [0, 0x3C0)
    localparam int SAFE_BYTES = 262;            // spec 7.1: fewer accepted bytes keep the state
    localparam int MAXTOK = 16;

    reg clk = 1'b0, rst_n = 1'b0;
    always #20 clk = ~clk;

    `include "abort_pads.svh"

    longint cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // ---------------------------------------------------------------- vectors
    reg [7:0]  plan   [0:MAXTOK-1];
    reg [15:0] stream [0:MAXTOK*WORDS-1];
    reg [15:0] golden [0:MAXTOK*VOCAB-1];
    reg [15:0] gstate [0:MAXTOK*SWORDS-1];
    reg [7:0]  upc_sec [0:255];
    reg [19:0] sbound [0:10];
    reg [7:0]  rbuf [0:2*SWORDS-1];
    string     sec_name [0:15];
    integer    tok_base;                        // first stream word of the current token
    integer    ntok;

    function automatic [7:0] sbyte(input integer i);
        reg [15:0] w;
        w = stream[tok_base + i / 2];
        sbyte = i[0] ? w[7:0] : w[15:8];
    endfunction

    integer errors = 0;
    string scen = "init";                       // current scenario name (messages)
    task automatic fail(input string msg);
        $display("FAIL: [%0s] %0s (cycle %0d)", scen, msg, cyc);
        errors++;
    endtask

    `include "qspi_host.svh"
    `include "abort_rng.svh"
    `include "abort_mon.svh"
    `include "abort_host.svh"
    `include "abort_gold.svh"
    `include "abort_scen.svh"

    string vec;
    integer fd, i, nrand, seed, sid;
    string nm;

    initial begin
        if (!$value$plusargs("VEC=%s", vec)) vec = "src/tb/build/abort_vec";
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("NRAND=%d", nrand)) nrand = 40;
        fd = $fopen({vec, "/plan.memh"}, "r");
        if (fd == 0) begin $display("FAIL: no %s/plan.memh", vec); $finish; end
        ntok = 0;
        while (ntok < MAXTOK && $fscanf(fd, "%h\n", plan[ntok]) == 1) ntok++;
        $fclose(fd);
        $readmemh({vec, "/stream.memh"}, stream, 0, ntok * WORDS - 1);
        $readmemh({vec, "/logits.memh"}, golden, 0, ntok * VOCAB - 1);
        $readmemh({vec, "/state.memh"}, gstate, 0, ntok * SWORDS - 1);
        $readmemh({vec, "/upc_sec.memh"}, upc_sec);
        $readmemh({vec, "/sbound.memh"}, sbound);
        for (i = 0; i < 16; i++) sec_name[i] = "?";
        fd = $fopen({vec, "/sections.txt"}, "r");
        while ($fscanf(fd, "%d %s\n", sid, nm) == 2) sec_name[sid] = nm;
        $fclose(fd);
        sec_ids();
        rng_seed(seed);
        $display("vectors %s: %0d tokens; seed %0d, %0d random scenarios", vec, ntok, seed, nrand);

        wclk(5);
        rst_n = 1'b1;
        mon_on = 1'b1;
        wclk(5);
        run_all(nrand);

        mon_report();
        if (errors == 0)
            $display("PASS: tb_mb_abort -- %0d scenarios, %0d aborts, %0d tokens bit-exact (logits + state), %0d state checks",
                     n_scen, n_abort, n_tok_ok, n_state_ok);
        else
            $display("FAIL: tb_mb_abort -- %0d error(s) in %0d scenarios", errors, n_scen);
        $finish;
    end
endmodule
