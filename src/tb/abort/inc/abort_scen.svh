// abort_scen.svh -- abort scenarios of tb_mb_abort and the run list (run_all).
// Every scenario ends with the chip idle, the expected state verified (spec 7.1) and at least
// one following token checked bit-exact (logits + state) against golden.

integer err0 = 0, land0 = 0;

task automatic scen_begin(input string name);
    scen = name;
    n_scen++;
    err0 = errors;
    land0 = n_land;
    scen_cyc0 = cyc;
endtask

task automatic scen_end;
    string at;
    at = "";
    if (n_land > land0)
        at = $sformatf(" last abort: %0s in %0s/%0s%0s", kind_name(last_kind), sname(last_sec),
                       act_name(last_act), trig_late ? " (trigger timed out)" : "");
    n_abort += n_land - land0;
    $display("SCEN %3d %-34s %0s  %0d clk, pos %0d%0s", n_scen, scen, errors == err0 ? "ok  " : "FAIL",
             cyc - scen_cyc0, pos, at);
    $fflush();
endtask

task automatic expect_landed(input integer n);
    if (n_land - land0 != n) fail($sformatf("%0d abort landing(s), expected %0d", n_land - land0, n));
endtask

function automatic string trig_name(input integer t);
    if (t == T_NOW) trig_name = "now";
    else trig_name = act_name(t);
endfunction

// make sure a full token can follow at pos (else start the story again)
task automatic room_for_token;
    if (!st_ok || pos >= ntok) g_reset(1'b0);
endtask

// a completed token with valid logits is in memory (for the idle-abort scenarios)
task automatic need_done_token;
    room_for_token();
    if (!lg_ok || pos == 0) g_token(1'b0);
endtask

task automatic release_soft(input string what);
    wr_csr(8'h01, 8'h04);
    expect_csr(8'h01, 8'h04, 8'hFF, {what, ": CTRL after release"});
endtask

// stream bytes while the soft reset is held: dropped, no err_ovf, byte count stays 0
task automatic stream_while_held(input integer from, input bit done);
    stream_k(from, from + 6, 0);
    wclk(4);
    expect_csr(8'h02, {6'd1, done, 1'b0}, 8'h37, "STATUS after stream bytes during soft reset");
    expect_bytes(0, "stream bytes during soft reset");
endtask

// after a lost state: recover, unless the abort landed before the first state write
task automatic after_token_abort(input bit keep);
    if (keep) begin
        g_chk_state("state kept (abort before byte 262)");
        g_token(1'b1);
    end else begin
        g_lost();
        g_recover();
    end
endtask

// ---------------------------------------------------------------- soft reset (CTRL[0])
// token step aborted after n stream bytes; the soft reset lands at trigger trig + delay
task automatic sc_soft_tok(input integer n, input integer trig, input integer delay, input bit hold_io);
    bit keep;
    scen_begin($sformatf("soft@%0d/%0s+%0d", n, trig_name(trig), delay));
    room_for_token();
    keep = st_ok && n < SAFE_BYTES;
    tok_base = pos * WORDS;
    lg_ok = 1'b0;
    cmd_only(8'h31);
    stream_k(0, n, 0);
    armed_frame(F_WR, 8'h02, 8'h01, 8'h05, trig, delay, 0);
    expect_landed(1);
    expect_csr(8'h01, 8'h05, 8'hFF, "CTRL while soft reset");
    g_chk_idle(1'b0, 0, "soft reset held");
    if (hold_io) stream_while_held(n, 1'b0);
    release_soft("soft");
    g_chk_idle(1'b0, 0, "soft reset released");
    after_token_abort(keep);
    scen_end();
endtask

// soft reset while idle after a completed token: done, logits and state are kept; requests
// while it is held (v bit 0: START, 1: stream bytes, 2: CTRL = 0x07) are not executed
task automatic sc_soft_idle(input integer v, input integer delay);
    scen_begin($sformatf("soft_idle/v%0d+%0d", v, delay));
    need_done_token();
    wclk(delay);
    armed_frame(F_WR, 8'h02, 8'h01, 8'h05, T_NOW, 0, 0);
    expect_landed(1);
    expect_csr(8'h02, 8'h06, 8'h37, "STATUS idle soft reset (done kept)");
    g_chk_logits("idle soft reset");
    if (v[0]) begin
        cmd_only(8'h31);
        wclk(8);
        g_chk_idle(1'b0, 0, "START during soft reset (not executed, done cleared)");
    end
    if (v[1]) stream_while_held(0, !v[0]);
    if (v[2]) begin
        wr_csr(8'h01, 8'h07);                   // STATE_RESET with the soft reset held: ignored
        wclk(8);
        expect_csr(8'h01, 8'h05, 8'hFF, "CTRL after 0x07");
        expect_csr(8'h02, 8'h04, 8'h37, "STATUS after STATE_RESET during soft reset");
    end
    g_chk_state("idle soft reset");
    g_chk_logits("idle soft reset, after held requests");
    release_soft("soft_idle");
    g_chk_state("after release");
    room_for_token();
    g_token(1'b1);
    scen_end();
endtask

// CTRL = 0x07 from idle (soft reset and STATE_RESET in one write): no run starts
task automatic sc_soft_sr_same_write;
    scen_begin("soft+STATE_RESET same write");
    need_done_token();
    land_arm = 1'b1;
    wr_csr(8'h01, 8'h07);
    wclk(8);
    land_arm = 1'b0;
    expect_csr(8'h01, 8'h05, 8'hFF, "CTRL after 0x07");
    g_chk_idle(1'b0, 0, "after 0x07 (done cleared, nothing executed)");
    g_chk_state("after 0x07 (state reset not executed)");
    g_chk_logits("after 0x07");
    release_soft("0x07");
    room_for_token();
    g_token(1'b1);
    scen_end();
endtask

// soft reset during the state-reset routine (delay clk after the CTRL write)
task automatic sc_soft_sr(input integer delay);
    scen_begin($sformatf("soft_in_reset+%0d", delay));
    wr_csr(8'h01, 8'h06);
    armed_frame(F_WR, 8'h02, 8'h01, 8'h05, T_NOW, delay, 0);
    expect_landed(1);
    g_chk_idle(last_act == A_IDLE, 0, "soft reset in state reset");
    release_soft("soft_in_reset");
    if (last_act == A_IDLE) begin           // the routine had completed: state = 0
        pos = 0; st_ok = 1'b1; lg_ok = 1'b0;
        g_chk_state("state reset completed before the soft reset");
        g_token(1'b1);
    end else begin
        g_lost();
        g_recover();
    end
    scen_end();
endtask

// ---------------------------------------------------------------- STATE_RESET while busy
task automatic sc_sr_tok(input integer n, input integer trig, input integer delay);
    scen_begin($sformatf("STATE_RESET@%0d/%0s+%0d", n, trig_name(trig), delay));
    room_for_token();
    tok_base = pos * WORDS;
    cmd_only(8'h31);
    stream_k(0, n, 0);
    armed_frame(F_WR, 8'h02, 8'h01, 8'h06, trig, delay, 0);
    expect_landed(1);
    wait_hrdy_to("STATE_RESET mid-token");
    g_chk_idle(1'b1, 0, "STATE_RESET mid-token");
    pos = 0; st_ok = 1'b1; lg_ok = 1'b0;
    g_chk_state("STATE_RESET mid-token");
    g_token(1'b1);
    scen_end();
endtask

task automatic sc_sr_sr(input integer delay);
    scen_begin($sformatf("STATE_RESET_in_reset+%0d", delay));
    wr_csr(8'h01, 8'h06);
    armed_frame(F_WR, 8'h02, 8'h01, 8'h06, T_NOW, delay, 0);
    expect_landed(1);
    wait_hrdy_to("STATE_RESET during STATE_RESET");
    g_chk_idle(1'b1, 0, "STATE_RESET during STATE_RESET");
    pos = 0; st_ok = 1'b1; lg_ok = 1'b0;
    g_chk_state("STATE_RESET during STATE_RESET");
    g_token(1'b1);
    scen_end();
endtask

// ---------------------------------------------------------------- START while busy
// token stream for the restarted step (no further START); checked if the state was kept
task automatic restart_body(input bit chk);
    bit ok;
    ok = st_ok;
    st_ok = chk && st_ok;
    tok_base = pos * WORDS;
    stream_k(0, TBYTES, 0);
    wait_hrdy_to("restarted token");
    expect_csr(8'h02, 8'h06, 8'h37, "STATUS after restarted token");
    expect_bytes(TBYTES, "restarted token");
    if (st_ok) begin
        rd_mem_q(16'h0800, 2 * VOCAB);
        begin : cmp
            integer i, mism;
            mism = 0;
            for (i = 0; i < VOCAB; i++) if ({rbuf[2*i], rbuf[2*i+1]} !== golden[pos * VOCAB + i]) mism++;
            if (mism) fail($sformatf("restarted token %0d: %0d logits differ", pos, mism));
            else n_tok_ok++;
        end
        pos++; lg_ok = 1'b1;
        g_chk_state("after restarted token");
    end else begin
        st_ok = ok;
        g_lost();
    end
endtask

task automatic sc_start_tok(input integer n, input integer trig, input integer delay);
    bit keep;
    scen_begin($sformatf("START@%0d/%0s+%0d", n, trig_name(trig), delay));
    room_for_token();
    keep = st_ok && n < SAFE_BYTES;
    tok_base = pos * WORDS;
    lg_ok = 1'b0;
    cmd_only(8'h31);
    stream_k(0, n, 0);
    armed_frame(F_CMD, 8'h31, 8'h00, 8'h00, trig, delay, 0);
    expect_landed(1);
    expect_csr(8'h02, 8'h25, 8'h37, "STATUS after START while busy (token step, byte count 0)");
    expect_bytes(0, "START while busy");
    restart_body(keep);
    if (!keep) g_recover();
    scen_end();
endtask

task automatic sc_start_sr(input integer delay);
    bit full;
    scen_begin($sformatf("START_in_reset+%0d", delay));
    wr_csr(8'h01, 8'h06);
    armed_frame(F_CMD, 8'h31, 8'h00, 8'h00, T_NOW, delay, 0);
    expect_landed(1);
    full = (last_act == A_IDLE);                // the routine had completed: token 0 from zero state
    pos = 0; st_ok = 1'b1;
    restart_body(full);
    if (!full) g_recover();
    scen_end();
endtask

// ---------------------------------------------------------------- rst_n
task automatic chk_after_rstn(input string what);
    expect_csr(8'h00, 8'h4D, 8'hFF, {what, ": ID"});
    expect_csr(8'h01, 8'h04, 8'hFF, {what, ": CTRL reset value"});
    expect_csr(8'h02, 8'h04, 8'hFF, {what, ": STATUS reset value"});
    g_chk_idle(1'b0, 0, what);
    g_lost();
    g_recover();
endtask

// rst_n while the host streams a token (trigger after min_bytes accepted)
task automatic sc_rstn_tok(input integer min_bytes, input integer trig, input integer delay,
                           input integer width, input integer sub);
    scen_begin($sformatf("rst_n@%0d/%0s+%0d w%0d", min_bytes, trig_name(trig), delay, width));
    room_for_token();
    tok_base = pos * WORDS;
    cmd_only(8'h31);
    rstn_arm(trig, delay, min_bytes, width, sub);
    stream_k(0, TBYTES, 0);
    rstn_join();
    expect_landed(1);
    chk_after_rstn("rst_n mid-token");
    scen_end();
endtask

// rst_n during a logit readback (chip driving IO) / RD_CSR / WR_CSR / state reset / idle
localparam int R_RDMQ = 0, R_RDCSR = 1, R_WRCSR = 2, R_SR = 3, R_IDLE = 4;
task automatic sc_rstn_other(input integer what, input integer delay, input integer width, input integer sub);
    reg [31:0] v;
    string wn;
    case (what)
        R_RDMQ: wn = "readback";  R_RDCSR: wn = "rd_csr";  R_WRCSR: wn = "wr_csr";
        R_SR:   wn = "in_reset";  default: wn = "idle";
    endcase
    scen_begin($sformatf("rst_n_%0s+%0d w%0d", wn, delay, width));
    if (what == R_RDMQ || what == R_IDLE) need_done_token();
    if (what == R_SR) wr_csr(8'h01, 8'h06);
    rstn_arm(T_NOW, delay, 0, width, sub);
    case (what)
        R_RDMQ:  rd_mem_q(16'h0800, 2 * VOCAB);
        R_RDCSR: rd_csr(8'h00, 4, v);
        R_WRCSR: wr_csr(8'h01, 8'h04);
        default: ;
    endcase
    rstn_join();
    expect_landed(1);
    if (what == R_RDMQ && oe_at_rst !== 4'hF) fail("rst_n did not land in the readback data phase");
    chk_after_rstn("rst_n");
    scen_end();
endtask

// ---------------------------------------------------------------- CS_N deasserted mid-frame
// every command cut at every (or a sample of) beat(s) while idle: no side effect at all
task automatic sc_cut_idle;
    integer j, n;
    scen_begin("cs_cut_idle (all commands)");
    room_for_token();
    g_token(1'b0);                              // logits valid, err_cmd cleared by its START
    for (j = 1; j < 8; j++) begin
        cut_frame(F_CMD, 8'h31, 0, 0, j);       // START
        cut_frame(F_CMD, 8'h32, 0, 0, j);       // STREAM_Q
        cut_frame(F_CMD, 8'hA5, 0, 0, j);       // bad command: no err_cmd unless complete
        cut_frame(F_CMD, 8'h6B, 0, 0, j);
    end
    for (j = 8; j < 24; j++) cut_frame(F_WR, 8'h02, 16'h0001, 8'h07, j);   // CTRL = 0x07, cut
    for (j = 1; j < 16 + 8 + 16; j += 3) cut_frame(F_RD, 8'h0B, 16'h0002, 0, j);
    for (j = 1; j < 12 + 4 + 12; j++) cut_frame(F_RDMQ, 8'h6B, 16'h0800, 0, j);
    for (j = 1; j < 24 + 8 + 16; j += 2) cut_frame(F_RDM, 8'h03, 16'h0800, 0, j);
    for (j = 0; j < 8; j++) begin
        n = rng(1, 24 + 8 + 8 * 40);
        cut_frame(F_RDMQ, 8'h6B, rng(0, 959) * 2, 0, n);
    end
    expect_csr(8'h01, 8'h04, 8'hFF, "CTRL after cut frames");
    expect_csr(8'h02, 8'h06, 8'h3F, "STATUS after cut frames (done kept, no err_cmd)");
    g_chk_idle(1'b1, TBYTES, "after cut frames");
    g_chk_logits("after cut frames");
    g_chk_state("after cut frames");
    room_for_token();
    g_token(1'b1);
    scen_end();
endtask

// one token streamed in pieces: each frame ends after a partial byte (CS_N mid-byte); the host
// resumes from the byte count.  Between frames: STATUS / byte-count polls, memory reads while
// busy, a bad command, writes to RO / unmapped CSRs, CTRL = quad_en (no-op) and cut frames.
task automatic sc_cut_stream(input integer nsplit, input bit quad);
    integer cur, nxt, part, j, k, n;
    reg [31:0] v;
    scen_begin($sformatf("cs_cut_stream x%0d %0s", nsplit, quad ? "quad" : "1-bit"));
    room_for_token();
    if (!quad) begin wr_csr(8'h01, 8'h00); h_quad = 1'b0; end
    tok_base = pos * WORDS;
    cmd_only(8'h31);
    cur = 0;
    for (j = 0; j <= nsplit; j++) begin
        nxt = (j == nsplit) ? TBYTES : cur + rng(0, 2 * (TBYTES - cur) / (nsplit - j + 1));
        if (nxt > TBYTES) nxt = TBYTES;
        part = (nxt >= TBYTES) ? 0 : h_quad ? 1 : rng(1, 7);
        stream_k(cur, nxt, part);
        if (nxt < TBYTES) begin
            expect_bytes(nxt, "partial byte dropped");
            expect_csr(8'h02, 8'h21, 8'h33, "STATUS mid-token");
            k = rng(0, 6);
            case (k)
                0: begin                                          // read while busy: no effect
                    n = rng(0, 2047);
                    rd_mem_q(n, rng(1, 8));
                end
                1: cmd_only(8'hA5);                               // bad command: err_cmd only
                2: begin wr_csr(8'h02, 8'hFF); wr_csr(8'h40, 8'h07); end   // RO / unmapped
                3: begin                                          // CTRL rewrite, no reset bits:
                    h_quad = !h_quad;                             // switch the stream mode
                    wr_csr(8'h01, h_quad ? 8'h04 : 8'h00);        // mid-token
                end
                4: cut_frame(F_CMD, 8'h31, 0, 0, rng(1, 7));      // partial START
                5: cut_frame(F_WR, 8'h02, 16'h0001, 8'h07, rng(8, 23));
                default: rd_csr(8'h06, 1, v);                     // microcode pc poll
            endcase
            rd_csr(8'h03, 3, v);
            cur = v[19:0];                      // resume from the byte count
        end
    end
    wait_hrdy_to("cut stream token");
    if (!h_quad) begin wr_csr(8'h01, 8'h04); h_quad = 1'b1; end
    expect_csr(8'h02, 8'h06, 8'h37, "STATUS after the split token");
    expect_bytes(TBYTES, "split token");
    rd_mem_q(16'h0800, 2 * VOCAB);
    begin : cmp
        integer i, mism;
        mism = 0;
        for (i = 0; i < VOCAB; i++) if ({rbuf[2*i], rbuf[2*i+1]} !== golden[pos * VOCAB + i]) mism++;
        if (mism) fail($sformatf("split token %0d: %0d logits differ", pos, mism));
        else n_tok_ok++;
    end
    pos++; lg_ok = 1'b1;
    g_chk_state("after split token");
    scen_end();
endtask

// a logit readback cut after n bytes + a nibble, then re-read in full
task automatic sc_cut_readback(input integer n);
    scen_begin($sformatf("cs_cut_readback@%0d", n));
    need_done_token();
    cut_frame(F_RDMQ, 8'h6B, 16'h0800, 0, 8 + 4 + 4 + 2 * n + 1);
    g_chk_logits("re-read after cut readback");
    g_chk_idle(1'b1, TBYTES, "after cut readback");
    room_for_token();
    g_token(1'b1);
    scen_end();
endtask

// ---------------------------------------------------------------- stream errors
// bytes while idle (no START) are dropped; an overrun (HRDY ignored) sets err_ovf, then the
// host aborts with the soft reset and recovers
task automatic sc_idle_stream;
    reg [31:0] v;
    scen_begin("stream_while_idle");
    need_done_token();
    rd_csr(8'h03, 3, v);
    stream_k(0, 40, 0);
    expect_csr(8'h02, 8'h06, 8'h37, "STATUS after idle stream bytes");
    expect_bytes(v[19:0], "idle stream bytes (byte count unchanged)");
    g_chk_logits("idle stream");
    g_chk_state("idle stream");
    room_for_token();
    g_token(1'b1);
    scen_end();
endtask

task automatic sc_overrun;
    integer i;
    scen_begin("overrun (HRDY ignored)");
    room_for_token();
    tok_base = pos * WORDS;
    cmd_only(8'h31);
    cs_begin(); tx_byte1(8'h32);
    for (i = 0; i < 400; i++) stream_byte(sbyte(i));      // no HRDY check: FIFO overruns in norm0
    cs_end();
    expect_csr(8'h02, 8'h35, 8'h37, "STATUS err_ovf");
    armed_frame(F_WR, 8'h02, 8'h01, 8'h05, T_NOW, 0, 0);
    g_chk_idle(1'b0, 0, "soft reset after overrun (err_ovf cleared)");
    release_soft("overrun");
    g_lost();
    g_recover();
    scen_end();
endtask

// back-to-back aborts: START, restart, STATE_RESET mid-routine soft reset, rst_n, ...
task automatic sc_chain;
    integer d, w;
    scen_begin("chain");
    room_for_token();
    tok_base = pos * WORDS;
    cmd_only(8'h31);
    stream_k(0, rng(300, 30000), 0);
    armed_frame(F_CMD, 8'h31, 0, 0, T_NOW, 0, 0);                  // restart
    stream_k(0, rng(300, 30000), 0);
    armed_frame(F_WR, 8'h02, 8'h01, 8'h06, T_NOW, 0, 0);           // -> state reset
    armed_frame(F_WR, 8'h02, 8'h01, 8'h05, T_NOW, rng(0, 1500), 0);  // soft reset in it
    release_soft("chain");
    cmd_only(8'h31);
    stream_k(0, rng(300, 30000), 0);
    d = rng(0, 50);
    w = rng(1, 4);
    rstn_arm(T_NOW, d, 0, w, rng(1, 15));                         // rst_n mid-stream
    stream_k(rng(0, 1), TBYTES, 0);
    rstn_join();
    expect_landed(4);
    chk_after_rstn("chain");
    scen_end();
endtask

// ---------------------------------------------------------------- run list
// stream offsets: section starts (sbound) and the CHAN / IN_X record geometry
localparam int CHAN_REC = 2 * 74, INX_REC = 2 * 67;

task automatic run_all(input integer nrand);
    integer s, j, k, n, t, f, d, w, u, b, o;
    // power-up: STATE_RESET, first token
    scen_begin("power-up");
    expect_csr(8'h00, 8'h4D, 8'hFF, "ID");
    expect_csr(8'h01, 8'h04, 8'hFF, "CTRL reset value");
    expect_csr(8'h02, 8'h04, 8'hFF, "STATUS reset value");
    g_reset(1'b1);
    g_token(1'b1);
    mem_uninit = 1'b0;                          // every region the TB reads is written now
    scen_end();

    // soft reset at fixed offsets (sequencer stalled on the stream), early to the tail
    sc_soft_tok(0, T_NOW, 0, 1);
    sc_soft_tok(1, T_NOW, 0, 0);
    sc_soft_tok(2, T_NOW, 0, 1);
    sc_soft_tok(127, T_NOW, 0, 0);
    sc_soft_tok(SAFE_BYTES - 1, T_NOW, 0, 0);
    sc_soft_tok(SAFE_BYTES, T_NOW, 0, 0);
    for (s = 0; s < 10; s++) begin
        sc_soft_tok(sbound[s] + 1, T_NOW, 0, s == 3);
        sc_soft_tok((sbound[s] + sbound[s + 1]) / 2, T_NOW, rng(0, 20), 0);
    end
    sc_soft_tok(TBYTES - 2, T_NOW, 0, 0);
    sc_soft_tok(TBYTES - 1, T_NOW, 0, 0);
    // soft reset during compute: norms (rsqrt), scan (exp2, state write), lane in flight
    sc_soft_tok(128, A_NLU_RSQ, 0, 0);
    sc_soft_tok(128, T_NOW, 300, 0);
    sc_soft_tok(sbound[5], A_NLU_RSQ, 2, 0);
    sc_soft_tok(sbound[9], A_NLU_RSQ, 0, 0);
    sc_soft_tok(sbound[9], T_NOW, 500, 0);
    for (j = 0; j < 3; j++) begin
        sc_soft_tok(sbound[3] + CHAN_REC * rng(0, 95) + 18, A_NLU_EXP, 0, 0);
        sc_soft_tok(sbound[7] + CHAN_REC * rng(0, 95) + 18, A_STW, 0, 0);
        sc_soft_tok(sbound[3] + CHAN_REC * rng(0, 95) + 18, A_LANE, 0, 0);
    end
    sc_soft_tok(sbound[7] + CHAN_REC * 10 + 10, A_NLU_SP, 0, 0);
    sc_soft_tok(sbound[1] + INX_REC * 5 + INX_REC, A_NLU_SIG, 0, 0);

    // soft reset while idle (+ requests while held), during the state reset, 0x07 write
    for (j = 0; j < 8; j++) sc_soft_idle(j, rng(0, 100));
    sc_soft_sr_same_write();
    sc_soft_sr(0);
    sc_soft_sr(1200);                           // consecutive delays: P0 and P1 (state write)
    sc_soft_sr(1201);
    sc_soft_sr(1202);
    sc_soft_sr(2600);
    sc_soft_sr(5000);                           // after the routine: lands idle, state 0

    // STATE_RESET mid-token, during a state reset
    sc_sr_tok(0, T_NOW, 0);
    sc_sr_tok(1, T_NOW, 0);
    sc_sr_tok(128, A_NLU_RSQ, 0);
    for (s = 0; s < 10; s += 2) sc_sr_tok(sbound[s] + rng(1, sbound[s + 1] - sbound[s] - 1), T_NOW, 0);
    sc_sr_tok(sbound[3] + CHAN_REC * 7 + 18, A_NLU_EXP, 0);
    sc_sr_tok(TBYTES - 1, T_NOW, 0);
    sc_sr_sr(0);
    sc_sr_sr(1500);

    // START while busy (restart): kept state below byte 262, else recover
    sc_start_tok(0, T_NOW, 0);
    sc_start_tok(2, T_NOW, 0);
    sc_start_tok(SAFE_BYTES - 1, T_NOW, 0);
    sc_start_tok(128, A_NLU_RSQ, 0);
    sc_start_tok(sbound[3] + CHAN_REC * 50 + 18, A_NLU_EXP, 0);
    sc_start_tok(sbound[9] + rng(0, 16000), T_NOW, 0);
    sc_start_tok(TBYTES - 1, T_NOW, 0);
    sc_start_sr(0);
    sc_start_sr(1000);
    sc_start_sr(4000);                          // after the routine: token 0 bit-exact

    // rst_n: at every sequencer activity, in every section, sub-cycle and multi-cycle pulses
    sc_rstn_tok(0, A_STALL_S, 0, 1, 3);
    sc_rstn_tok(100, T_NOW, 0, 3, 11);
    sc_rstn_tok(120, A_NLU_RSQ, 0, 1, 5);
    sc_rstn_tok(sbound[1] + 500, A_NLU_SIG, 0, 2, 9);
    sc_rstn_tok(sbound[1] + 900, A_STW, 0, 0, 2);
    sc_rstn_tok(sbound[2] + 300, A_LANE, 0, 1, 15);
    sc_rstn_tok(sbound[3] + 3000, A_NLU_SP, 0, 1, 1);
    sc_rstn_tok(sbound[3] + 5000, A_NLU_EXP, 1, 4, 7);
    sc_rstn_tok(sbound[3] + 7000, A_STW, 0, 1, 10);
    sc_rstn_tok(sbound[4] + 700, A_LANE, 0, 0, 6);
    sc_rstn_tok(sbound[5] - 80, A_NLU_RSQ, 0, 1, 4);
    sc_rstn_tok(sbound[7] + 9000, A_NLU_EXP, 0, 2, 12);
    sc_rstn_tok(sbound[9] - 80, A_NLU_RSQ, 3, 1, 8);
    sc_rstn_tok(sbound[9] + 400, A_LOGW, 0, 1, 3);
    sc_rstn_tok(TBYTES - 130, A_LOGW, 0, 0, 5);
    sc_rstn_tok(TBYTES - 2, A_STALL_S, 0, 1, 14);
    for (s = 0; s < 10; s++) begin
        n = sbound[s] + rng(0, sbound[s + 1] - sbound[s] - 1);
        d = rng(0, 40);
        w = rng(0, 3);
        sc_rstn_tok(n, T_NOW, d, w, rng(1, 15));
    end
    sc_rstn_other(R_RDMQ, 131, 1, 7);           // first data nibble
    sc_rstn_other(R_RDMQ, 205, 0, 3);
    sc_rstn_other(R_RDMQ, 2000, 2, 13);
    sc_rstn_other(R_RDCSR, 150, 1, 4);
    sc_rstn_other(R_WRCSR, 50, 0, 9);
    sc_rstn_other(R_SR, 300, 1, 6);
    sc_rstn_other(R_SR, 2000, 3, 2);
    sc_rstn_other(R_IDLE, 10, 1, 1);

    // CS_N mid-frame
    sc_cut_idle();
    sc_cut_stream(12, 1);
    sc_cut_stream(6, 0);
    sc_cut_readback(0);
    sc_cut_readback(77);
    sc_cut_readback(255);

    // stream errors, chains
    sc_idle_stream();
    sc_overrun();
    sc_chain();

    // seeded random mix
    // (every draw is made up front, in a fixed order: argument evaluation order differs
    //  between simulators)
    for (j = 0; j < nrand; j++) begin
        f = rng(0, 9);
        n = rng(0, TBYTES - 1);
        t = rng(0, 3);
        t = (t == 0) ? T_NOW : rng(A_STALL_S, A_STW);
        if (t == A_STALL_Y) t = A_LANE;
        d = rng(0, 200);
        w = rng(0, 4);
        u = rng(1, 15);
        b = rng(0, 1);
        k = rng(0, 3);
        o = rng(R_RDMQ, R_IDLE);
        case (f)
            0, 1: sc_soft_tok(n, t, d, b);
            2: sc_sr_tok(n, t, d);
            3: sc_start_tok(b ? n : n % SAFE_BYTES, t, d);
            4, 5: sc_rstn_tok(n, t, d, w, u);
            6: sc_rstn_other(o, o == R_RDMQ ? 130 + n % 4070 : n % 3001, w % 4, u);
            7: sc_cut_stream(1 + n % 8, 1);
            8: begin
                if (k == 0) sc_soft_sr(n % 3001);
                else if (k == 1) sc_sr_sr(n % 3001);
                else if (k == 2) sc_start_sr(n % 3001);
                else sc_soft_idle(n % 8, d);
            end
            default: sc_chain();
        endcase
    end

    // final: a clean two-token run from STATE_RESET
    scen_begin("final");
    g_reset(1'b1);
    g_token(1'b1);
    g_token(1'b1);
    scen_end();
endtask
