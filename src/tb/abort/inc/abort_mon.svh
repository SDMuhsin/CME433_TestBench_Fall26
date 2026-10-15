// abort_mon.svh -- monitors of tb_mb_abort:
//   * X / Z on any chip output (all pad terminals) after the first reset -> FAIL
//   * IO contention (chip and host driving the same IO pad) -> FAIL
//   * while rst_n is low: every IO driver off and HRDY high (idle) -> else FAIL
//   * landing classifier: when an abort reaches the core (soft reset rising,
//     STATE_RESET / START pulse, rst_n falling) it records the program section
//     (microcode pc -> src/ucode/program.py section) and the sequencer activity
//     in that cycle; mon_report() prints the coverage and fails if a required
//     abort point was never hit.
// Hierarchical references into dut are read-only and used for checks only.

bit mon_on = 1'b0;
integer contention = 0, xerrs = 0, xinit = 0, xoff = 0;
// X check: every pad control output (OE, IE, pulls, ..., HRDY) and every *driven* IO bit
// (OUT where OE = 1) must be 0/1 after the first reset.  An OUT value with its OE off does
// not reach the pin; it is only counted (xoff).
// Before the first token has run, activations (XN, X, U, DBC) were never written and the SRAM
// model reads them as X.  A memory read prefetches one byte past its range (mb_host_qspi), so
// the power-up state read-back (bytes 0..1919) drives XN's X byte on IO for a few clk after its
// last sampled nibble.  Only that is tolerated (counted in xinit).
bit mem_uninit = 1'b1;                          // cleared after the power-up token

// ---------------------------------------------------------------- abort kinds / activities
localparam int K_SOFT = 0, K_SR = 1, K_START = 2, K_RSTN = 3, NKIND = 4;
localparam int A_IDLE = 0, A_STALL_S = 1, A_STALL_Y = 2, A_NLU_SIG = 3, A_NLU_SP = 4,
               A_NLU_EXP = 5, A_NLU_RSQ = 6, A_LANE = 7, A_LOGW = 8, A_STW = 9, A_MEMW = 10,
               A_OP = 11, NACT = 12;
localparam int SEC_IDLE = 15, NSEC = 16;

function automatic string kind_name(input integer k);
    case (k)
        K_SOFT: kind_name = "soft_reset";  K_SR: kind_name = "STATE_RESET";
        K_START: kind_name = "START";      default: kind_name = "rst_n";
    endcase
endfunction

function automatic string act_name(input integer a);
    case (a)
        A_IDLE: act_name = "idle";            A_STALL_S: act_name = "wait_stream";
        A_STALL_Y: act_name = "wait_lane";    A_NLU_SIG: act_name = "nlu_sigmoid";
        A_NLU_SP: act_name = "nlu_softplus";  A_NLU_EXP: act_name = "nlu_exp2";
        A_NLU_RSQ: act_name = "nlu_rsqrt";    A_LANE: act_name = "lane_in_flight";
        A_LOGW: act_name = "logit_write";     A_STW: act_name = "state_write";
        A_MEMW: act_name = "act_write";       default: act_name = "uop";
    endcase
endfunction

integer sec_logits = -1, sec_reset = -1;       // section ids, set by sec_ids()
task automatic sec_ids;
    integer j;
    for (j = 0; j < NSEC; j++) begin
        if (sec_name[j] == "logits") sec_logits = j;
        if (sec_name[j] == "reset")  sec_reset = j;
    end
endtask

function automatic string sname(input integer s);
    if (s == SEC_IDLE) sname = "idle";
    else sname = sec_name[s];
endfunction

// ---------------------------------------------------------------- X / contention / reset checks

always @(posedge clk) if (|(chip_oe & host_oe)) contention = contention + 1;

always @(negedge clk) begin
    if (mon_on && (^(chip_out & ~chip_oe) === 1'bx)) xoff = xoff + 1;
    if (mon_on && mem_uninit && (^{chip_oe, HRDY, nc} !== 1'bx) && (^(chip_out & chip_oe) === 1'bx) &&
        dut.u_host.state == 3'd5 && dut.u_host.rd_mem)
        xinit = xinit + 1;
    else if (mon_on && (^{chip_out & chip_oe, chip_oe, HRDY, nc} === 1'bx)) begin
        xerrs = xerrs + 1;
        if (xerrs <= 5) fail($sformatf("X/Z on chip outputs: out %b oe %b HRDY %b", chip_out, chip_oe, HRDY));
    end
    if (mon_on && !rst_n && (chip_oe !== 4'h0 || HRDY !== 1'b1))
        fail($sformatf("during rst_n: IO oe %b (expected 0), HRDY %b (expected 1)", chip_oe, HRDY));
end

// ---------------------------------------------------------------- landing classifier
`define SEQ dut.u_core.u_seq
reg [1:0] nlu_fn_r = 2'd0;
bit       nlu_busy = 1'b0;                      // between NLD and its MOV Y.WBN
integer   snap_sec = SEC_IDLE, snap_act = A_IDLE;
bit       prev_soft = 1'b0, prev_rstn = 1'b0;

function automatic integer cur_act;
    reg [10:0] a;
    a = `SEQ.m_addr;
    if (!`SEQ.run)                                      cur_act = A_IDLE;
    else if (`SEQ.m_we && a >= 11'h400 && a < 11'h480 && upc_sec[`SEQ.pc] == sec_logits)
                                                        cur_act = A_LOGW;
    else if (`SEQ.m_we && a < 11'h3C0)                  cur_act = A_STW;
    else if (`SEQ.m_we)                                 cur_act = A_MEMW;
    else if (nlu_busy || `SEQ.nlu_ld)                   cur_act = A_NLU_SIG + (`SEQ.nlu_ld ? `SEQ.nlu_fn : nlu_fn_r);
    else if (!`SEQ.lane_idle)                           cur_act = A_LANE;
    else if (!`SEQ.ph && `SEQ.use_s && !`SEQ.s_ok)      cur_act = A_STALL_S;
    else if (!`SEQ.ph && `SEQ.use_y && !`SEQ.lane_idle) cur_act = A_STALL_Y;
    else                                                cur_act = A_OP;
endfunction

function automatic integer cur_sec;
    cur_sec = `SEQ.run ? upc_sec[`SEQ.pc] : SEC_IDLE;
endfunction

// coverage counters
integer cov_act [0:NKIND-1][0:NACT-1];
integer cov_sec [0:NKIND-1][0:NSEC-1];
integer n_land = 0;                             // landings seen (any kind) while land_arm
bit     land_arm = 1'b0;                        // set by scenarios around an injected abort
integer last_kind = 0, last_sec = SEC_IDLE, last_act = A_IDLE;
longint last_land_cyc = 0;
initial begin : cov_init
    integer k, j;
    for (k = 0; k < NKIND; k++) begin
        for (j = 0; j < NACT; j++) cov_act[k][j] = 0;
        for (j = 0; j < NSEC; j++) cov_sec[k][j] = 0;
    end
end

task automatic land(input integer kind, input integer s, input integer a);
    if (land_arm) begin
        cov_act[kind][a]++;
        cov_sec[kind][s]++;
        n_land++;
        last_kind = kind; last_sec = s; last_act = a; last_land_cyc = cyc;
    end
endtask

always @(negedge clk) begin
    if (rst_n) begin
        // the core sees these in the coming posedge (abort level / clr_state / start pulse)
        if (`SEQ.abort && !prev_soft)                      land(K_SOFT, cur_sec(), cur_act());
        if (dut.u_csr.clr_state && !`SEQ.abort)            land(K_SR, cur_sec(), cur_act());
        if (dut.u_host.seq_start && !`SEQ.abort)           land(K_START, cur_sec(), cur_act());
        prev_soft = `SEQ.abort;
        snap_sec  = cur_sec();
        snap_act  = cur_act();
        if (`SEQ.nlu_ld) begin nlu_busy = 1'b1; nlu_fn_r = `SEQ.nlu_fn; end
        else if (`SEQ.go1 && `SEQ.op == 3'd2 && `SEQ.sa == 3'd5 && `SEQ.mode == 2'd2) nlu_busy = 1'b0;
    end
    if (!`SEQ.run) nlu_busy = 1'b0;
end

// rst_n falls asynchronously: classify with the state of the last negedge snapshot
always @(negedge rst_n) if (mon_on) land(K_RSTN, snap_sec, snap_act);
always @(posedge rst_n) begin prev_soft = 1'b0; nlu_busy = 1'b0; end

// ---------------------------------------------------------------- report
task automatic mon_report;
    integer k, j, tot;
    string line;
    $display("ABORT COVERAGE (landing point of every injected abort: program section / sequencer activity)");
    for (k = 0; k < NKIND; k++) begin
        tot = 0;
        for (j = 0; j < NACT; j++) tot += cov_act[k][j];
        line = $sformatf("  %-11s %4d  act:", kind_name(k), tot);
        for (j = 0; j < NACT; j++) if (cov_act[k][j]) line = {line, $sformatf(" %0s=%0d", act_name(j), cov_act[k][j])};
        $display("%0s", line);
        line = "                   sec:";
        for (j = 0; j < NSEC; j++) if (cov_sec[k][j]) line = {line, $sformatf(" %0s=%0d", sname(j), cov_sec[k][j])};
        $display("%0s", line);
    end
    scen = "coverage";
    // required abort points (fail if a directed test stopped reaching its target)
    for (j = 0; j < NACT; j++)
        if (j != A_STALL_Y && j != A_MEMW && j != A_OP && cov_act[K_RSTN][j] == 0)
            fail($sformatf("rst_n never landed during %0s", act_name(j)));
    for (j = 0; j < NSEC; j++)
        if ((sname(j) != "?" && sname(j) != "end") && cov_sec[K_RSTN][j] == 0)
            fail($sformatf("rst_n never landed in section %0s", sname(j)));
    for (j = 0; j < NSEC; j++)
        if ((sname(j) != "?" && sname(j) != "end") && cov_sec[K_SOFT][j] == 0)
            fail($sformatf("soft reset never landed in section %0s", sname(j)));
    if (cov_act[K_SOFT][A_STALL_S] == 0 || cov_act[K_SOFT][A_IDLE] == 0 || cov_act[K_SOFT][A_NLU_RSQ] == 0 ||
        cov_act[K_SOFT][A_STW] == 0 || cov_act[K_SOFT][A_NLU_EXP] + cov_act[K_SOFT][A_LANE] == 0)
        fail("soft reset coverage: need wait_stream, idle, nlu_rsqrt, state_write and exp2 / lane points");
    for (k = K_SR; k <= K_START; k++)
        if (cov_act[k][A_STALL_S] == 0 || cov_sec[k][sec_reset] == 0)
            fail($sformatf("%0s coverage: need a token-step and a state-reset landing", kind_name(k)));
    if (contention) fail($sformatf("%0d cycles of IO pad contention", contention));
    if (xerrs) fail($sformatf("%0d cycles with X/Z on chip outputs", xerrs));
    $display("X CHECK: %0d cycles with X/Z on a driven IO bit or a pad control output; tolerated: %0d cycles of never-written SRAM data in the power-up read-back; %0d cycles with an X OUT value behind OE = 0",
             xerrs, xinit, xoff);
endtask
