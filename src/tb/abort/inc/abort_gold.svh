// abort_gold.svh -- golden bookkeeping and checks of tb_mb_abort.
//
// The TB runs one story (plan.memh) from zero state.  `pos` = tokens done since the last
// STATE_RESET; `st_ok` = the on-chip state is the golden state after `pos` tokens (else it is
// undefined, spec 7.1, and only a STATE_RESET makes it defined again).
//   g_reset         STATE_RESET (CTRL = 0x06), wait HRDY, STATUS, state == 0 (read back)
//   g_token         START + full stream at `pos`, done, STATUS, byte count, logits (+ state)
//                   bit-exact vs golden when st_ok
//   g_chk_state     state region (memory words 0..959) == golden after `pos` tokens
//   g_chk_logits    logits re-read == golden of token pos-1 (they stay until the next START)
//   g_chk_idle      STATUS / byte count and the host-link / sequencer / lane FSMs idle
//   g_recover       g_reset + one bit-exact token (the documented recovery after a lost state)

integer pos = 0;
bit     st_ok = 1'b0;
bit     lg_ok = 1'b0;                           // logits of token pos-1 are in memory
integer n_tok_ok = 0, n_state_ok = 0, n_scen = 0, n_abort = 0;

task automatic expect_csr(input [7:0] addr, input [7:0] exp, input [7:0] mask, input string what);
    reg [31:0] v;
    rd_csr(addr, 1, v);
    if ((v[7:0] & mask) !== exp)
        fail($sformatf("%0s: CSR %02x = %02x, expected %02x (mask %02x)", what, addr, v[7:0], exp, mask));
endtask

task automatic expect_bytes(input integer exp, input string what);
    reg [31:0] v;
    rd_csr(8'h03, 3, v);
    if (v[19:0] !== exp) fail($sformatf("%0s: byte count %0d, expected %0d", what, v[19:0], exp));
endtask

// STATUS bits [5:0] = tok, err_ovf, err_cmd, hrdy, done, busy; err_cmd is masked unless asked
task automatic g_chk_idle(input bit done, input integer bytes, input string what);
    expect_csr(8'h02, {2'b00, 1'b0, 1'b0, 1'b0, 1'b1, done, 1'b0}, 8'h37, {what, ": STATUS"});
    expect_bytes(bytes, what);
    if (dut.u_host.state !== 3'd0 || dut.u_host.bcnt !== 3'd0 || dut.u_host.quad !== 1'b0 ||
        dut.u_host.tx_quad !== 1'b0 || chip_oe !== 4'h0)
        fail($sformatf("%0s: host link not idle (state %0d bcnt %0d quad %b tx_quad %b oe %b)", what,
                       dut.u_host.state, dut.u_host.bcnt, dut.u_host.quad, dut.u_host.tx_quad, chip_oe));
    if (`SEQ.run !== 1'b0 || `SEQ.ph !== 1'b0 || `SEQ.tok !== 1'b0 || `SEQ.lane_issue !== 1'b0 ||
        dut.u_core.u_lane.v1 !== 1'b0 || dut.u_core.u_lane.v2 !== 1'b0)
        fail($sformatf("%0s: sequencer / lane not idle (run %b ph %b tok %b issue %b v1 %b v2 %b)", what,
                       `SEQ.run, `SEQ.ph, `SEQ.tok, `SEQ.lane_issue, dut.u_core.u_lane.v1, dut.u_core.u_lane.v2));
    if (dut.u_core.u_fifo.cnt !== 5'd0 || dut.u_core.u_fifo.err_ovf !== 1'b0)
        fail($sformatf("%0s: stream FIFO not empty / err_ovf (cnt %0d ovf %b)", what,
                       dut.u_core.u_fifo.cnt, dut.u_core.u_fifo.err_ovf));
    if (^{dut.u_csr.ctrl, dut.u_csr.err_cmd, `SEQ.done, dut.u_core.u_fifo.wp, dut.u_core.u_fifo.rp,
          dut.u_core.u_fifo.byte_cnt, dut.u_host.h_addr, dut.u_host.rd_pend, `SEQ.pc} === 1'bx)
        fail({what, ": X in control registers"});
endtask

task automatic g_chk_state(input string what);
    integer i, mism;
    reg [15:0] got, exp;
    if (st_ok) begin
        rd_mem_q(16'h0000, 2 * SWORDS);
        mism = 0;
        for (i = 0; i < SWORDS; i++) begin
            got = {rbuf[2*i], rbuf[2*i+1]};
            exp = (pos == 0) ? 16'h0000 : gstate[(pos - 1) * SWORDS + i];
            if (got !== exp) begin
                mism++;
                if (mism <= 3) fail($sformatf("%0s: state word %03x = %04x, golden %04x (after %0d tokens)",
                                              what, i, got, exp, pos));
            end
        end
        if (mism == 0) n_state_ok++;
        else fail($sformatf("%0s: %0d state words differ", what, mism));
    end
endtask

task automatic g_chk_logits(input string what);
    integer i, mism;
    reg [15:0] got, exp;
    if (st_ok && lg_ok && pos > 0) begin
        rd_mem_q(16'h0800, 2 * VOCAB);
        mism = 0;
        for (i = 0; i < VOCAB; i++) begin
            got = {rbuf[2*i], rbuf[2*i+1]};
            exp = golden[(pos - 1) * VOCAB + i];
            if (got !== exp) mism++;
        end
        if (mism) fail($sformatf("%0s: %0d / %0d logits of token %0d differ", what, mism, VOCAB, pos - 1));
    end
endtask

task automatic g_reset(input bit chk);
    wr_csr(8'h01, 8'h06);                       // STATE_RESET, keep quad_en
    wait_hrdy_to("state reset");
    expect_csr(8'h02, 8'h02, 8'h3B, "STATUS after state reset");
    pos = 0; st_ok = 1'b1;
    if (chk) g_chk_state("after STATE_RESET");
endtask

// a full token step at pos; checked when st_ok (else it only has to complete)
task automatic g_token(input bit chk_state);
    integer i, mism;
    reg [15:0] got;
    if (pos >= ntok) g_reset(1'b0);
    tok_base = pos * WORDS;
    cmd_only(8'h31);
    stream_k(0, TBYTES, 0);
    wait_hrdy_to("token step");
    expect_csr(8'h02, 8'h06, 8'h37, "STATUS after token");
    expect_bytes(TBYTES, "after token");
    rd_mem_q(16'h0800, 2 * VOCAB);
    if (st_ok) begin
        mism = 0;
        for (i = 0; i < VOCAB; i++) begin
            got = {rbuf[2*i], rbuf[2*i+1]};
            if (got !== golden[pos * VOCAB + i]) begin
                mism++;
                if (mism <= 3) fail($sformatf("token %0d logit %0d: got %04x golden %04x", pos, i, got,
                                              golden[pos * VOCAB + i]));
            end
        end
        if (mism) fail($sformatf("token %0d: %0d / %0d logits differ", pos, mism, VOCAB));
        else n_tok_ok++;
        pos++;
        lg_ok = 1'b1;
        if (chk_state) g_chk_state($sformatf("after token %0d", pos - 1));
    end else
        lg_ok = 1'b0;
endtask

task automatic g_recover;
    g_reset(1'b1);
    g_token(1'b1);
endtask

// the state is lost: logits / state checks are off until the next STATE_RESET
task automatic g_lost;
    st_ok = 1'b0; lg_ok = 1'b0;
endtask
