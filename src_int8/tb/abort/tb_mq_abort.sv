`timescale 1ns / 1ps

// ============================================================================
// tb_mq_abort -- abort / reset path test of mq_chip (spec.md section 8 = the
// FP16 spec's section 7.1 abort table; ported from src/tb/abort/tb_mb_abort.sv).
//
// The TB is the external host on the 11 pad terminals, as in tb_mq_chip.  It
// aborts the chip in every way the host can (soft reset, STATE_RESET and START
// while busy, rst_n, CS_N deassertion mid-frame, stream overrun) at many points
// of a token step -- directed offsets in every stream section, triggers on
// sequencer activity (NLU ops, lane in flight, logit / state writes) and
// seeded random offsets -- and after each abort checks:
//   * STATUS / CTRL / byte count / ID values, the host link and sequencer FSMs
//     idle (hierarchical), no hang (bounded waits, watchdog);
//   * the expected state: the on-chip SSM / conv state read back over RD_MEM_Q
//     (H slots 0x0000..0x0BFF, CONV 0x1140..0x11FF) equals golden (zero after
//     STATE_RESET, unchanged if the abort preserves it: fewer than 197 stream
//     bytes accepted), and the next tokens' logits and state are bit-exact vs
//     src_int8/golden;
//   * no X / Z on any chip output after the first reset (iverilog), no IO
//     contention, IO drivers off while rst_n is low.
// Vectors: python3 -m src_int8.tb.abort.gen_vectors (+VEC=<dir>).  +SEED=<n>
// (random part), +NRAND=<n> random scenarios (default 40).  Prints one line
// per scenario, a coverage table of where the aborts landed, and PASS / FAIL.
// ============================================================================
module tb_mq_abort;
    localparam int TBYTES = 54280;              // stream bytes per token
    localparam int VOCAB  = 128;
    localparam int HSLOTS = 'hC00;              // host bytes of the H slots (768 x 4)
    localparam int CONVB  = 192;                // CONV0 + CONV1 bytes
    localparam int SBYTES = HSLOTS + CONVB;     // state bytes per token in state.memh
    localparam int LOGITS_ADDR = 'h1040;
    localparam int CONV_ADDR   = 'h1140;
    localparam int SAFE_BYTES = 197;            // spec 8: fewer accepted bytes keep the state
    localparam int MAXTOK = 16;

    reg clk = 1'b0, rst_n = 1'b0;
    always #20 clk = ~clk;

    `include "abort_pads.svh"

    longint cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // ---------------------------------------------------------------- vectors
    reg [7:0]  plan   [0:MAXTOK-1];
    reg [7:0]  stream [0:MAXTOK*TBYTES-1];
    reg [15:0] golden [0:MAXTOK*VOCAB-1];
    reg [7:0]  gstate [0:MAXTOK*SBYTES-1];
    reg [7:0]  upc_sec [0:255];
    reg [19:0] sbound [0:10];
    reg [7:0]  rbuf [0:HSLOTS-1];
    string     sec_name [0:15];
    integer    tok_base;                        // first stream byte of the current token
    integer    ntok;

    function automatic [7:0] sbyte(input integer i);
        sbyte = stream[tok_base + i];
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
        if (!$value$plusargs("VEC=%s", vec)) vec = "src_int8/tb/build/abort_vec";
        if (!$value$plusargs("SEED=%d", seed)) seed = 1;
        if (!$value$plusargs("NRAND=%d", nrand)) nrand = 40;
        fd = $fopen({vec, "/plan.memh"}, "r");
        if (fd == 0) begin $display("FAIL: no %s/plan.memh", vec); $finish; end
        ntok = 0;
        while (ntok < MAXTOK && $fscanf(fd, "%h\n", plan[ntok]) == 1) ntok++;
        $fclose(fd);
        $readmemh({vec, "/stream.memh"}, stream, 0, ntok * TBYTES - 1);
        $readmemh({vec, "/logits.memh"}, golden, 0, ntok * VOCAB - 1);
        $readmemh({vec, "/state.memh"}, gstate, 0, ntok * SBYTES - 1);
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
            $display("PASS: tb_mq_abort -- %0d scenarios, %0d aborts, %0d tokens bit-exact (logits + state), %0d state checks",
                     n_scen, n_abort, n_tok_ok, n_state_ok);
        else
            $display("FAIL: tb_mq_abort -- %0d error(s) in %0d scenarios", errors, n_scen);
        $finish;
    end
endmodule
