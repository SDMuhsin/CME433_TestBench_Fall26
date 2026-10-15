`timescale 1ns / 1ps

// ============================================================================
// tb_mq_chip_sdf -- pad-level chip test of the routed mq_chip netlist with SDF
// back-annotation (src_int8/flow/sdf_gls/run_sdf_gls.sh, Open Source CVC).
// The same test as src_int8/tb/chip/tb_mq_chip.sv (CSR reset values, per token:
// [STATE_RESET], START, STREAM_Q of the 54,280-byte stream, wait HRDY, STATUS /
// byte count, RD_MEM_Q of the 256 logit bytes at 0x1040 (LE), bit-exact compare
// with the golden vectors; host-image read-back (H slots 0x0000..0x0BFF and
// BMEM 0x1040..0x11FF) after the last token of each story) in Verilog-2001,
// with SDC pad timing (qspi_host_sdf.vh) and an output-timing monitor
// (io_mon.vh).  Port of src/tb/sdf/tb_mb_chip_sdf.v (FP16 mb_chip).
//   +PLAN=, +STREAM=, +LOGITS=, +HOST=  vector files (python3 -m src_int8.golden.vectors <out>
//                               --chip-only, files in <out>/chip)
//   +NTOK=n                     run only the first n tokens of the plan
//   +MAXCYC=n                   stop (FAIL: incomplete) after n clk (negative timing tests)
//   +PROGRESS=n                 print the cycle count every n clk
//   +VCD=<file> +VCD_TOK=t      dump the mq_chip nets (scope tb.dut, depth 1) from
//                               START of token t to the end of its logit readback,
//                               then stop (switching activity for power)
//   +STATE_ALL=1                host-image read-back after every token
//   `TCLK (define)              clock period in ns, default 40 (TIN/TOUT = 20 %)
// Prints PASS/FAIL, cycles per token and the IO timing summary.
// ============================================================================
`ifndef TCLK
`define TCLK 40.0
`endif
module tb_mq_chip_sdf;
    localparam TBYTES = 54280;                  // stream bytes per token
    localparam VOCAB = 128;
    localparam MAXTOK = 64;
    localparam HOSTB = 'h1200;                  // host image bytes
    localparam LOGITS_ADDR = 'h1040;
    localparam real TCLK = `TCLK;
    localparam real TIN = 0.2 * TCLK;           // SDC set_input_delay
    localparam real TOUT = 0.2 * TCLK;          // SDC set_output_delay
    localparam real TSMP = TCLK - TIN - TOUT;   // tick -> sample point

    reg clk, rst_n;
    initial begin clk = 1'b0; rst_n = 1'b0; end
    always #(TCLK / 2.0) clk = ~clk;

    // ---------------------------------------------------------------- pads
    reg SCLK_IN, CS_N_IN;
    reg [3:0] host_io, host_oe;
    initial begin SCLK_IN = 1'b0; CS_N_IN = 1'b1; host_io = 4'h0; host_oe = 4'h0; end
    wire [3:0] chip_out, chip_oe, pad_io;
    wire HRDY;
    wire [43:0] nc;                             // pad controls (monitored for timing only)

    assign pad_io[0] = chip_oe[0] ? chip_out[0] : (host_oe[0] ? host_io[0] : 1'b0);
    assign pad_io[1] = chip_oe[1] ? chip_out[1] : (host_oe[1] ? host_io[1] : 1'b0);
    assign pad_io[2] = chip_oe[2] ? chip_out[2] : (host_oe[2] ? host_io[2] : 1'b0);
    assign pad_io[3] = chip_oe[3] ? chip_out[3] : (host_oe[3] ? host_io[3] : 1'b0);

    integer contention;
    initial contention = 0;
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

    wire [52:0] outs = {nc, chip_out, chip_oe, HRDY};
    `include "io_mon.vh"

    reg sram_cnt_en;
    initial sram_cnt_en = 1'b0;
    `include "sram_mon.vh"

    // HRDY as the host sees it: sampled TCLK - TOUT after each edge
    reg hrdy_s;
    initial hrdy_s = 1'b0;
    always @(posedge clk) begin #(TCLK - TOUT); hrdy_s = HRDY; end

    integer cyc, maxcyc, progress;
    initial begin
        cyc = 0;
        if (!$value$plusargs("MAXCYC=%d", maxcyc)) maxcyc = 0;
        if (!$value$plusargs("PROGRESS=%d", progress)) progress = 0;
    end
    always @(posedge clk) begin
        cyc = cyc + 1;
        if (progress > 0 && cyc % progress == 0) begin
            $display("PROGRESS %0d clk, %0.3f ms", cyc, $realtime * 1.0e-6);
            $fflush;
        end
        if (maxcyc > 0 && cyc >= maxcyc) begin
            $display("STOP: +MAXCYC=%0d reached at %0.3f ns; IO: worst output settle %0.3f ns, %0d output-timing violations",
                     maxcyc, $realtime, om_worst, om_viol);
            $display("FAIL: mq_chip -- incomplete run (MAXCYC)");
            $finish;
        end
    end

    // ---------------------------------------------------------------- vectors
    reg [8:0]  plan   [0:MAXTOK-1];
    reg [7:0]  stream [0:MAXTOK*TBYTES-1];
    reg [15:0] golden [0:MAXTOK*VOCAB-1];
    reg [7:0]  himg   [0:MAXTOK*HOSTB-1];
    reg [7:0]  rbuf   [0:HOSTB-1];
    integer    tok_base;                        // first stream byte of the current token

    function [7:0] sbyte(input integer i);
        sbyte = stream[tok_base + i];
    endfunction

    `include "qspi_host_sdf.vh"

    integer errors;
    initial errors = 0;

    task expect_csr(input [7:0] addr, input [7:0] exp, input [7:0] mask, input [8*32:1] what);
        reg [31:0] v;
        begin
            rd_csr(addr, 1, v);
            if ((v[7:0] & mask) !== exp) begin
                $display("FAIL: %0s: CSR %h = %h, expected %h (mask %h)", what, addr, v[7:0], exp, mask);
                errors = errors + 1;
            end
        end
    endtask

    task check_reset_csrs;
        begin
            expect_csr(8'h00, 8'h49, 8'hFF, "ID");
            expect_csr(8'h01, 8'h04, 8'hFF, "CTRL reset value");
            expect_csr(8'h02, 8'h04, 8'hFF, "STATUS reset value");
            cmd_only(8'hA5);
            expect_csr(8'h02, 8'h08, 8'h08, "err_cmd after a bad command");
            $display("CSR checks done (ID 0x49, CTRL, STATUS, err_cmd)");
        end
    endtask

    task state_reset;
        integer c0;
        begin
            c0 = cyc;
            wr_csr(8'h01, 8'h06);               // STATE_RESET, keep quad_en
            wait_hrdy;
            expect_csr(8'h02, 8'h02, 8'h3B, "STATUS after state reset");
            $display("  state reset: %0d clk", cyc - c0);
        end
    endtask

    // host image compare: H slots [0, 0xC00) and BMEM [0x1040, 0x1200)
    task check_state(input integer t);
        integer i, mism;
        begin
            mism = 0;
            rd_mem_q(16'h0000, 'hC00);
            for (i = 0; i < 'hC00; i = i + 1)
                if (rbuf[i] !== himg[t * HOSTB + i]) begin
                    mism = mism + 1;
                    if (mism <= 3) $display("  token %0d host byte %h: got %h exp %h", t, i, rbuf[i], himg[t * HOSTB + i]);
                end
            rd_mem_q(LOGITS_ADDR, HOSTB - LOGITS_ADDR);
            for (i = LOGITS_ADDR; i < HOSTB; i = i + 1)
                if (rbuf[i - LOGITS_ADDR] !== himg[t * HOSTB + i]) begin
                    mism = mism + 1;
                    if (mism <= 3) $display("  token %0d host byte %h: got %h exp %h", t, i, rbuf[i - LOGITS_ADDR], himg[t * HOSTB + i]);
                end
            if (mism) errors = errors + 1;
            $display("  state read-back after token %0d: %0d mismatching bytes of %0d", t, mism, 'hC00 + HOSTB - LOGITS_ADDR);
            $fflush;
        end
    endtask

    integer tok_cycles, tail_cycles, loop_cycles;
    initial begin tok_cycles = 0; tail_cycles = 0; loop_cycles = 0; end
    reg [8*512:1] vcd_file;
    integer vcd_tok;

    task run_token(input integer t);
        integer waits, i, mism;
        reg [31:0] v;
        reg [15:0] got, exp;
        integer c0, c1, c2, c3;
        real t0;
        begin
            tok_base = t * TBYTES;
            if (t == vcd_tok) begin
                $dumpfile(vcd_file);
                $dumpvars(1, tb_mq_chip_sdf.dut);
                $display("VCD: dumping tb_mq_chip_sdf.dut from %0.3f ns (token %0d)", $realtime, t);
            end
            t0 = $realtime;
            c0 = cyc;
            if (t == vcd_tok) sram_cnt_en = 1'b1;
            cmd_only(8'h31);                    // START
            stream_frame(0, TBYTES, waits);
            c1 = cyc;
            wait_hrdy;
            c2 = cyc;
            expect_csr(8'h02, 8'h06, 8'h3F, "STATUS after token");
            rd_csr(8'h03, 3, v);
            if (v[19:0] !== TBYTES) begin $display("FAIL: byte count %0d", v[19:0]); errors = errors + 1; end
            rd_mem_q(LOGITS_ADDR, 2 * VOCAB);
            c3 = cyc;
            if (t == vcd_tok) begin
                $dumpflush;
                sram_cnt_en = 1'b0;
                for (i = 0; i < 11; i = i + 1)
                    $display("SRAM %0d: %0d reads, %0d writes in the window", i, sram_rd[i], sram_wr[i]);
                $display("VCD: window %0d clk", cyc - c0);
                $display("VCD: window %0.3f .. %0.3f ns = %0.6f ms (token %0d incl. status + readback)",
                         t0, $realtime, ($realtime - t0) * 1.0e-6, t);
            end
            mism = 0;
            for (i = 0; i < VOCAB; i = i + 1) begin
                got = {rbuf[2*i+1], rbuf[2*i]};     // little endian
                exp = golden[t * VOCAB + i];
                if (got !== exp) begin
                    mism = mism + 1;
                    if (mism <= 5) $display("  token %0d logit %0d: got %h exp %h", t, i, got, exp);
                end
            end
            if (mism) errors = errors + 1;
            tok_cycles = tok_cycles + (c2 - c0);
            tail_cycles = tail_cycles + (c2 - c1);
            loop_cycles = loop_cycles + (c3 - c0);
            $display("TOKEN %0d byte %h: %0d/%0d logits bit-exact; START->done %0d clk (stream %0d, tail %0d), +status/readback %0d, %0d HRDY waits",
                     t, plan[t][7:0], VOCAB - mism, VOCAB, c2 - c0, c1 - c0, c2 - c1, c3 - c2, waits);
            $fflush;
        end
    endtask

    reg [8*512:1] f_plan, f_stream, f_logits, f_host;
    integer ntok, nmax, t, nreset, nstate, state_all, fd, r;
    reg [8:0] pw;

    initial begin
        if (!$value$plusargs("PLAN=%s", f_plan) || !$value$plusargs("STREAM=%s", f_stream) ||
            !$value$plusargs("LOGITS=%s", f_logits) || !$value$plusargs("HOST=%s", f_host)) begin
            $display("FAIL: need +PLAN= +STREAM= +LOGITS= +HOST="); $finish;
        end
        if (!$value$plusargs("NTOK=%d", nmax)) nmax = MAXTOK;
        if (!$value$plusargs("VCD_TOK=%d", vcd_tok)) vcd_tok = -1;
        if (!$value$plusargs("VCD=%s", vcd_file)) vcd_tok = -1;
        if (!$value$plusargs("STATE_ALL=%d", state_all)) state_all = 0;
        fd = $fopen(f_plan, "r");
        if (fd == 0) begin $display("FAIL: cannot open %0s", f_plan); $finish; end
        ntok = 0;
        r = $fscanf(fd, "%h\n", pw);
        while (ntok < MAXTOK && ntok < nmax && r == 1) begin
            plan[ntok] = pw; ntok = ntok + 1;
            r = $fscanf(fd, "%h\n", pw);
        end
        $fclose(fd);
        $readmemh(f_stream, stream, 0, ntok * TBYTES - 1);
        $readmemh(f_logits, golden, 0, ntok * VOCAB - 1);
        $readmemh(f_host, himg, 0, ntok * HOSTB - 1);
        $display("vectors: %0d tokens, clock %0.3f ns, input delay %0.3f ns, output delay %0.3f ns",
                 ntok, TCLK, TIN, TOUT);

        wclk(5);
        rst_n = 1'b1;
        wclk(5);
        check_reset_csrs;

        nreset = 0; nstate = 0;
        for (t = 0; t < ntok; t = t + 1) begin
            if (plan[t][8]) begin state_reset; nreset = nreset + 1; end
            run_token(t);
            if (t == vcd_tok) ntok = t + 1;     // activity window done: stop here
            else if (state_all || t == ntok - 1 || plan[t + 1][8]) begin check_state(t); nstate = nstate + 1; end
        end

        if (contention) begin $display("FAIL: %0d cycles of IO pad contention", contention); errors = errors + 1; end
        if (om_viol) begin $display("FAIL: %0d output-timing violations", om_viol); errors = errors + 1; end
        $display("IO: worst output settle after clk %0.3f ns (limit %0.3f = period - output delay), %0d output-timing violations",
                 om_worst, TCLK - TOUT, om_viol);
        if (ntok > 0)
            $display("CYCLES/TOKEN %0d START->done (%0.3f ms), %0d incl. status + logit readback (%0.3f ms); avg of %0d tokens, tail after last byte %0d clk",
                     tok_cycles / ntok, (tok_cycles / ntok) * TCLK * 1.0e-6, loop_cycles / ntok,
                     (loop_cycles / ntok) * TCLK * 1.0e-6, ntok, tail_cycles / ntok);
        if (errors == 0)
            $display("PASS: mq_chip -- %0d tokens x %0d logits bit-exact vs golden, %0d state resets, %0d state read-backs", ntok, VOCAB, nreset, nstate);
        else
            $display("FAIL: mq_chip -- %0d error(s)", errors);
        $finish;
    end
endmodule
