`timescale 1ns / 1ps

// ============================================================================
// tb_mq_demo -- closed-loop pad-level host for mq_chip, driven by a Python host
// (src_int8/demo/host/closed_loop.py, long_run.py) over two named pipes.
// Adapted from the FP16 chip's tb_mb_demo (byte stream, INT16 logits at 0x1040).
//
// +BASE=<memh>  one token's weight stream, 54,280 bytes (bytes 0..127 = E_in row)
// +EMB=<memh>   E_in table as bytes, 128 x 128 (64 x INT16 LE per byte value):
//               the only token-dependent part of the stream
// +CMD=<fifo>   host -> TB, one hex word per token: bit 9 quit, bit 8 state reset, 7..0 byte
// +RSP=<fifo>   TB -> host, per token two lines:
//                 "T <START->done clk> <stream clk> <incl. readback clk> <HRDY waits> <errors>"
//                 128 INT16 logits read back from the chip (4 hex digits, space separated)
// The TB checks nothing about the logits; the host compares them with src_int8/golden and
// samples the next byte from them.  Clock 25 MHz.
// ============================================================================
module tb_mq_demo;
    localparam int TBYTES = 54280;
    localparam int VOCAB = 128;
    localparam int EMBB = 128;                  // embedding row bytes (64 x INT16)
    localparam int LOGITS_ADDR = 'h1040;

    reg clk = 1'b0, rst_n = 1'b0;
    always #20 clk = ~clk;

    // ---------------------------------------------------------------- pads
    reg SCLK_IN = 1'b0, CS_N_IN = 1'b1;
    reg [3:0] host_io = 4'h0, host_oe = 4'h0;
    wire [3:0] chip_out, chip_oe, pad_io;
    wire HRDY;
    wire [43:0] nc;

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

    // ---------------------------------------------------------------- stream source
    reg [7:0] base [0:TBYTES-1];
    reg [7:0] emb  [0:VOCAB*EMBB-1];
    reg [7:0] rbuf [0:2*VOCAB-1];
    integer   cur_tok;

    function automatic [7:0] sbyte(input integer i);
        sbyte = (i < EMBB) ? emb[cur_tok * EMBB + i] : base[i];
    endfunction

    `include "qspi_host.svh"

    integer errors = 0;

    task automatic expect_csr(input [7:0] addr, input [7:0] exp, input [7:0] mask, input string what);
        reg [31:0] v;
        rd_csr(addr, 1, v);
        if ((v[7:0] & mask) !== exp) begin
            $display("ERROR: %s: CSR %02x = %02x, expected %02x (mask %02x)", what, addr, v[7:0], exp, mask);
            errors++;
        end
    endtask

    task automatic state_reset;
        wr_csr(8'h01, 8'h06);                   // STATE_RESET, keep quad_en
        wait_hrdy();
        expect_csr(8'h02, 8'h02, 8'h3B, "STATUS after state reset");
    endtask

    // one token: START, stream, wait done, status/count check, logit read-back into rbuf
    task automatic run_token(output longint c_done, output longint c_stream, output longint c_all,
                             output integer waits);
        reg [31:0] v;
        longint c0;
        c0 = cyc;
        cmd_only(8'h31);
        stream_frame(0, TBYTES, waits);
        c_stream = cyc - c0;
        wait_hrdy();
        c_done = cyc - c0;
        expect_csr(8'h02, 8'h06, 8'h3F, "STATUS after token");
        rd_csr(8'h03, 3, v);
        if (v[19:0] !== TBYTES) begin $display("ERROR: byte count %0d", v[19:0]); errors++; end
        rd_mem_q(LOGITS_ADDR, 2 * VOCAB);
        c_all = cyc - c0;
    endtask

    string base_f, emb_f, cmd_f, rsp_f;
    integer cmd, rsp, n, i, waits, ntok, err0;
    reg [15:0] word;
    longint c_done, c_stream, c_all;

    initial begin
        if (!$value$plusargs("BASE=%s", base_f) || !$value$plusargs("EMB=%s", emb_f) ||
            !$value$plusargs("CMD=%s", cmd_f) || !$value$plusargs("RSP=%s", rsp_f)) begin
            $display("FAIL: need +BASE +EMB +CMD +RSP"); $finish;
        end
        $readmemh(base_f, base);
        $readmemh(emb_f, emb);
        cmd = $fopen(cmd_f, "r");               // same open order as the host: CMD, then RSP
        rsp = $fopen(rsp_f, "w");
        if (cmd == 0 || rsp == 0) begin $display("FAIL: cannot open pipes"); $finish; end

        wclk(5);
        rst_n = 1'b1;
        wclk(5);
        expect_csr(8'h00, 8'h49, 8'hFF, "ID");

        ntok = 0;
        forever begin
            n = $fscanf(cmd, "%h", word);
            if (n != 1 || word[9]) break;
            err0 = errors;
            if (word[8]) state_reset();
            cur_tok = word[7:0];
            run_token(c_done, c_stream, c_all, waits);
            $fwrite(rsp, "T %0d %0d %0d %0d %0d\n", c_done, c_stream, c_all, waits, errors - err0);
            for (i = 0; i < VOCAB; i = i + 1)   // little endian in memory -> INT16 hex
                $fwrite(rsp, "%02x%02x%s", rbuf[2*i+1], rbuf[2*i], i == VOCAB - 1 ? "\n" : " ");
            $fflush(rsp);
            $display("TOKEN %0d byte %02x: START->done %0d clk, incl. readback %0d clk", ntok, cur_tok[7:0],
                     c_done, c_all);
            ntok++;
        end
        if (contention) begin $display("ERROR: %0d cycles of IO pad contention", contention); errors++; end
        $display("%s: tb_mq_demo -- %0d tokens, %0d TB error(s)", errors ? "FAIL" : "DONE", ntok, errors);
        $fwrite(rsp, "E %0d %0d\n", ntok, errors);
        $fflush(rsp);
        $finish;
    end
endmodule
