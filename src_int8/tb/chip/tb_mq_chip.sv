`timescale 1ns / 1ps

// ============================================================================
// tb_mq_chip -- pad-level chip test of mq_chip against the golden vectors.
//
// The TB is the external host and only touches the 11 pad terminals (quad IO
// resolved here with a contention check).  Vectors (+VEC=<dir>, format of
// src_int8/golden/vectors/chip.py): plan.memh (per token: bit 8 = state reset
// before, bits 7..0 = byte), stream.memh (one byte per line), logits.memh
// (INT16 Q7.8), host.memh (0x1200-byte host image after every token).
//   1. ID / CTRL / STATUS reset values, err_cmd on a bad command.
//   2. per token: [CTRL.STATE_RESET, wait HRDY], START, STREAM_Q of the
//      54,280-byte stream (HRDY honoured before every byte), wait HRDY,
//      STATUS / byte-count check, RD_MEM_Q of the 256 logit bytes at 0x1040
//      (LE), bit-exact compare; on the last token of each story (or every
//      token with +STATE_ALL) RD_MEM_Q of the host image: H slots 0x0000..
//      0x0BFF and BMEM 0x1040..0x11FF (XN at 0x1000..0x103F is not checked).
// Prints "PASS: ..." / "FAIL: ..." and the cycles per token.  Clock 25 MHz.
// ============================================================================
module tb_mq_chip;
    localparam int TBYTES = 54280;              // stream bytes per token
    localparam int VOCAB = 128;
    localparam int MAXTOK = 64;
    localparam int HOSTB = 'h1200;              // host image bytes
    localparam int LOGITS_ADDR = 'h1040;
    localparam real TCLK_NS = 40.0;

    reg clk = 1'b0, rst_n = 1'b0;
    always #20 clk = ~clk;

    // ---------------------------------------------------------------- pads
    reg SCLK_IN = 1'b0, CS_N_IN = 1'b1;
    reg [3:0] host_io = 4'h0, host_oe = 4'h0;
    wire [3:0] chip_out, chip_oe, pad_io;
    wire HRDY;
    wire [43:0] nc;                             // pad controls not checked here

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : G_PAD
            assign pad_io[gi] = chip_oe[gi] ? chip_out[gi] : (host_oe[gi] ? host_io[gi] : 1'b0);
        end
    endgenerate

    integer contention = 0;
    always @(posedge clk) if (|(chip_oe & host_oe)) contention = contention + 1;

    mq_chip dut (
        .clk(clk), .clk_PU(nc[0]), .clk_PD(nc[1]), .rst_n(rst_n), .rst_n_PU(nc[2]), .rst_n_PD(nc[3]),
        .SCLK_IN(SCLK_IN), .SCLK_OUT(nc[4]), .SCLK_OE(nc[5]), .SCLK_IE(nc[6]), .SCLK_CS(nc[7]),
        .SCLK_SL(nc[8]), .SCLK_PU(nc[9]), .SCLK_PD(nc[10]),
        .MOSI_IN(pad_io[0]), .MOSI_OUT(chip_out[0]), .MOSI_OE(chip_oe[0]), .MOSI_IE(nc[11]),
        .MOSI_CS(nc[12]), .MOSI_SL(nc[13]), .MOSI_PU(nc[14]), .MOSI_PD(nc[15]),
        .CS_N_IN(CS_N_IN), .CS_N_OUT(nc[16]), .CS_N_OE(nc[17]), .CS_N_IE(nc[18]), .CS_N_CS(nc[19]),
        .CS_N_SL(nc[20]), .CS_N_PU(nc[21]), .CS_N_PD(nc[22]),
        .MISO_IN(pad_io[1]), .MISO_OUT(chip_out[1]), .MISO_OE(chip_oe[1]), .MISO_IE(nc[23]),
        .MISO_CS(nc[24]), .MISO_SL(nc[25]), .MISO_PU(nc[26]), .MISO_PD(nc[27]),
        .busy_IN(pad_io[2]), .busy_OUT(chip_out[2]), .busy_OE(chip_oe[2]), .busy_IE(nc[28]),
        .busy_CS(nc[29]), .busy_SL(nc[30]), .busy_PU(nc[31]), .busy_PD(nc[32]),
        .done_IN(pad_io[3]), .done_OUT(chip_out[3]), .done_OE(chip_oe[3]), .done_IE(nc[33]),
        .done_CS(nc[34]), .done_SL(nc[35]), .done_PU(nc[36]), .done_PD(nc[37]),
        .wb_done_IN(1'b0), .wb_done_OUT(HRDY), .wb_done_OE(nc[38]), .wb_done_IE(nc[39]),
        .wb_done_CS(nc[40]), .wb_done_SL(nc[41]), .wb_done_PU(nc[42]), .wb_done_PD(nc[43]));

    longint cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // ---------------------------------------------------------------- vectors
    reg [8:0]  plan   [0:MAXTOK-1];
    reg [7:0]  stream [0:MAXTOK*TBYTES-1];
    reg [15:0] golden [0:MAXTOK*VOCAB-1];
    reg [7:0]  himg   [0:MAXTOK*HOSTB-1];
    reg [7:0]  rbuf   [0:HOSTB-1];
    integer    tok_base;                        // first stream byte of the current token

    function automatic [7:0] sbyte(input integer i);
        sbyte = stream[tok_base + i];
    endfunction

    `include "qspi_host.svh"

    integer errors = 0;

    task automatic expect_csr(input [7:0] addr, input [7:0] exp, input [7:0] mask, input string what);
        reg [31:0] v;
        rd_csr(addr, 1, v);
        if ((v[7:0] & mask) !== exp) begin
            $display("FAIL: %s: CSR %02x = %02x, expected %02x (mask %02x)", what, addr, v[7:0], exp, mask);
            errors++;
        end
    endtask

    task automatic check_reset_csrs;
        expect_csr(8'h00, 8'h49, 8'hFF, "ID");
        expect_csr(8'h01, 8'h04, 8'hFF, "CTRL reset value");
        expect_csr(8'h02, 8'h04, 8'hFF, "STATUS reset value");
        cmd_only(8'hA5);
        expect_csr(8'h02, 8'h08, 8'h08, "err_cmd after a bad command");
        $display("CSR checks done (ID 0x49, CTRL, STATUS, err_cmd)");
    endtask

    task automatic state_reset;
        longint c0;
        c0 = cyc;
        wr_csr(8'h01, 8'h06);                   // STATE_RESET, keep quad_en
        wait_hrdy();
        expect_csr(8'h02, 8'h02, 8'h3B, "STATUS after state reset");
        $display("  state reset: %0d clk", cyc - c0);
    endtask

    // host image compare: H slots [0, 0xC00) and BMEM [0x1040, 0x1200)
    task automatic check_state(input integer t);
        integer i, mism;
        mism = 0;
        rd_mem_q(16'h0000, 'hC00);
        for (i = 0; i < 'hC00; i = i + 1)
            if (rbuf[i] !== himg[t * HOSTB + i]) begin
                mism++;
                if (mism <= 3) $display("  token %0d host byte %04x: got %02x exp %02x", t, i, rbuf[i], himg[t * HOSTB + i]);
            end
        rd_mem_q(LOGITS_ADDR, HOSTB - LOGITS_ADDR);
        for (i = LOGITS_ADDR; i < HOSTB; i = i + 1)
            if (rbuf[i - LOGITS_ADDR] !== himg[t * HOSTB + i]) begin
                mism++;
                if (mism <= 3) $display("  token %0d host byte %04x: got %02x exp %02x", t, i, rbuf[i - LOGITS_ADDR], himg[t * HOSTB + i]);
            end
        if (mism) errors++;
        $display("  state read-back after token %0d: %0d mismatching bytes of %0d", t, mism, 'hC00 + HOSTB - LOGITS_ADDR);
    endtask

    longint tok_cycles = 0, tail_cycles = 0, loop_cycles = 0;

    task automatic run_token(input integer t);
        integer waits, i, mism;
        reg [31:0] v;
        reg [15:0] got, exp;
        longint c0, c1, c2, c3;
        tok_base = t * TBYTES;
        c0 = cyc;
        cmd_only(8'h31);                        // START
        stream_frame(0, TBYTES, waits);
        c1 = cyc;
        wait_hrdy();
        c2 = cyc;
        expect_csr(8'h02, 8'h06, 8'h3F, "STATUS after token");
        rd_csr(8'h03, 3, v);
        if (v[19:0] !== TBYTES) begin $display("FAIL: byte count %0d", v[19:0]); errors++; end
        rd_mem_q(LOGITS_ADDR, 2 * VOCAB);
        c3 = cyc;
        mism = 0;
        for (i = 0; i < VOCAB; i = i + 1) begin
            got = {rbuf[2*i+1], rbuf[2*i]};     // little endian
            exp = golden[t * VOCAB + i];
            if (got !== exp) begin
                mism++;
                if (mism <= 5) $display("  token %0d logit %0d: got %04x exp %04x", t, i, got, exp);
            end
        end
        if (mism) errors++;
        tok_cycles += c2 - c0;
        tail_cycles += c2 - c1;
        loop_cycles += c3 - c0;
        $display("TOKEN %0d byte %02x: %0d/%0d logits bit-exact; START->done %0d clk (stream %0d, tail %0d), +status/readback %0d, %0d HRDY waits",
                 t, plan[t][7:0], VOCAB - mism, VOCAB, c2 - c0, c1 - c0, c2 - c1, c3 - c2, waits);
    endtask

    string vec;
    integer ntok, t, nreset, fd, state_all, nstate;

    initial begin
        if (!$value$plusargs("VEC=%s", vec)) vec = "src_int8/tb/build/vec/chip";
        if (!$value$plusargs("STATE_ALL=%d", state_all)) state_all = 0;
        fd = $fopen({vec, "/plan.memh"}, "r");
        if (fd == 0) begin $display("FAIL: no %s/plan.memh", vec); $finish; end
        ntok = 0;
        while (ntok < MAXTOK && $fscanf(fd, "%h\n", plan[ntok]) == 1) ntok++;
        $fclose(fd);
        $readmemh({vec, "/stream.memh"}, stream, 0, ntok * TBYTES - 1);
        $readmemh({vec, "/logits.memh"}, golden, 0, ntok * VOCAB - 1);
        $readmemh({vec, "/host.memh"}, himg, 0, ntok * HOSTB - 1);
        $display("vectors %s: %0d tokens", vec, ntok);

        wclk(5);
        rst_n = 1'b1;
        wclk(5);
        check_reset_csrs();

        nreset = 0; nstate = 0;
        for (t = 0; t < ntok; t = t + 1) begin
            if (plan[t][8]) begin state_reset(); nreset++; end
            run_token(t);
            if (state_all || t == ntok - 1 || plan[t + 1][8]) begin check_state(t); nstate++; end
        end

        if (contention) begin $display("FAIL: %0d cycles of IO pad contention", contention); errors++; end
        $display("CYCLES/TOKEN %0d START->done (%0.3f ms @ 25 MHz), %0d incl. status + logit readback (%0.3f ms); avg of %0d tokens, tail after last byte %0d clk",
                 tok_cycles / ntok, (tok_cycles / ntok) * TCLK_NS * 1.0e-6, loop_cycles / ntok,
                 (loop_cycles / ntok) * TCLK_NS * 1.0e-6, ntok, tail_cycles / ntok);
        if (errors == 0)
            $display("PASS: mq_chip -- %0d tokens x %0d logits bit-exact vs golden, %0d state resets, %0d state read-backs", ntok, VOCAB, nreset, nstate);
        else
            $display("FAIL: mq_chip -- %0d error(s)", errors);
        $finish;
    end
endmodule
