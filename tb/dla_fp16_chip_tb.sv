`timescale 1ns / 1ps

// ============================================================================
// dla_fp16_chip_tb -- pad-level host model for the FP16 END-TO-END G300 GAN chip.
//
// The testbench is the external 3.3 V host and only touches the 11 pad terminals
// (IO[3:0] = MOSI/MISO/busy/done resolved here with a contention check):
//   1. ID / CTRL / STATUS reset values over RD_CSR, CTRL rw, err_cmd on a bad command,
//   2. per image: START, STREAM_Q of the 567,968-B FP16 stream (z + per neuron
//      {bias, weights}, MSB byte first; from scripts/gen_fp16_stream.py), HRDY
//      honoured before every byte, wait for HRDY / STATUS.done, byte count check,
//      then RD_PIX_Q of the 784 uint8 pixels (SCLK = clk/8) compared bit-exactly.
//
// Plusargs:
//   +STREAM_SRC=<file>  567,968-B stream memh (default sim/results/fp16/mnist/seed_0/stream.memh)
//   +EXPECTED=<file>    784 uint8 golden pixels (default <same dir>/expected_pix.memh)
//   +H0=<file> +H2=<file>  optional: check the FP16 h0 (pair P1) / h2 (pair P0) left in SRAM
//   +ACTUAL_MEMH=<file> dump the 784 pixels read back
//   +HALF=<n>    stream SCLK half period in clk (2 -> clk/4 [default], 4 -> clk/8)
//   +IMAGES=<n>  back-to-back images (default 1); images >= 2 use random-length frames + pauses
//   +SPLIT=1     also split image 1
//   +ABORT=1     before image 1: START, stream ~100 kB (mid L2), abandon, restart
// `define GLS: flat-netlist hierarchical names for the +H0/+H2 checks.
// Clock 25 MHz (40 ns).  Run from the repo root.
// ============================================================================
module dla_fp16_chip_tb;
    localparam int NPIX = 784;
    localparam int TOTAL = 567968;
    localparam real TCLK_NS = 40.0;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #20 clk = ~clk;

    // ---------------------------------------------------------------- pads
    reg SCLK_IN = 1'b0, CS_N_IN = 1'b1;
    reg [3:0] host_io = 4'h0, host_oe = 4'h0;
    wire [3:0] chip_out, chip_oe;
    wire [3:0] pad_io;
    wire wb_done_IN = 1'b0;

    wire clk_PU, clk_PD, rst_n_PU, rst_n_PD;
    wire SCLK_OUT, SCLK_OE, SCLK_IE, SCLK_CS, SCLK_SL, SCLK_PU, SCLK_PD;
    wire MOSI_IE, MOSI_CS, MOSI_SL, MOSI_PU, MOSI_PD;
    wire CS_N_OUT, CS_N_OE, CS_N_IE, CS_N_CS, CS_N_SL, CS_N_PU, CS_N_PD;
    wire MISO_IE, MISO_CS, MISO_SL, MISO_PU, MISO_PD;
    wire busy_IE, busy_CS, busy_SL, busy_PU, busy_PD;
    wire done_IE, done_CS, done_SL, done_PU, done_PD;
    wire HRDY, wb_done_OE, wb_done_IE, wb_done_CS, wb_done_SL, wb_done_PU, wb_done_PD;

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : G_PAD
            assign pad_io[gi] = chip_oe[gi] ? chip_out[gi] : (host_oe[gi] ? host_io[gi] : 1'b0);
        end
    endgenerate

    integer contention = 0;
    always @(posedge clk) if (|(chip_oe & host_oe)) contention = contention + 1;

    dla_fp16_chip dut (
        .clk(clk), .clk_PU(clk_PU), .clk_PD(clk_PD),
        .rst_n(rst_n), .rst_n_PU(rst_n_PU), .rst_n_PD(rst_n_PD),
        .SCLK_IN(SCLK_IN), .SCLK_OUT(SCLK_OUT), .SCLK_OE(SCLK_OE), .SCLK_IE(SCLK_IE),
        .SCLK_CS(SCLK_CS), .SCLK_SL(SCLK_SL), .SCLK_PU(SCLK_PU), .SCLK_PD(SCLK_PD),
        .MOSI_IN(pad_io[0]), .MOSI_OUT(chip_out[0]), .MOSI_OE(chip_oe[0]), .MOSI_IE(MOSI_IE),
        .MOSI_CS(MOSI_CS), .MOSI_SL(MOSI_SL), .MOSI_PU(MOSI_PU), .MOSI_PD(MOSI_PD),
        .CS_N_IN(CS_N_IN), .CS_N_OUT(CS_N_OUT), .CS_N_OE(CS_N_OE), .CS_N_IE(CS_N_IE),
        .CS_N_CS(CS_N_CS), .CS_N_SL(CS_N_SL), .CS_N_PU(CS_N_PU), .CS_N_PD(CS_N_PD),
        .MISO_IN(pad_io[1]), .MISO_OUT(chip_out[1]), .MISO_OE(chip_oe[1]), .MISO_IE(MISO_IE),
        .MISO_CS(MISO_CS), .MISO_SL(MISO_SL), .MISO_PU(MISO_PU), .MISO_PD(MISO_PD),
        .busy_IN(pad_io[2]), .busy_OUT(chip_out[2]), .busy_OE(chip_oe[2]), .busy_IE(busy_IE),
        .busy_CS(busy_CS), .busy_SL(busy_SL), .busy_PU(busy_PU), .busy_PD(busy_PD),
        .done_IN(pad_io[3]), .done_OUT(chip_out[3]), .done_OE(chip_oe[3]), .done_IE(done_IE),
        .done_CS(done_CS), .done_SL(done_SL), .done_PU(done_PU), .done_PD(done_PD),
        .wb_done_IN(wb_done_IN), .wb_done_OUT(HRDY), .wb_done_OE(wb_done_OE), .wb_done_IE(wb_done_IE),
        .wb_done_CS(wb_done_CS), .wb_done_SL(wb_done_SL), .wb_done_PU(wb_done_PU), .wb_done_PD(wb_done_PD)
    );

    // ---------------------------------------------------------------- cycle counter
    longint cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // ---------------------------------------------------------------- host BFM
    // All host pad changes happen on the falling clk edge (no race with the
    // chip's rising-edge synchronizers).  `half` = SCLK half period in clk.
    integer half = 2;
    integer stream_half = 2;
    localparam int RD_HALF = 4;          // reads: SCLK = clk/8

    task automatic wclk(input integer n);
        repeat (n) @(negedge clk);
    endtask

    task automatic cs_begin;
        CS_N_IN = 1'b0; SCLK_IN = 1'b0; wclk(half);
    endtask

    task automatic cs_end;
        wclk(half);
        host_oe = 4'h0;
        CS_N_IN = 1'b1;
        wclk(4);
    endtask

    // one SCLK cycle, data already set up: low half then high half
    task automatic sclk_cycle;
        SCLK_IN = 1'b0; wclk(half);
        SCLK_IN = 1'b1; wclk(half);
    endtask

    task automatic tx_byte1(input [7:0] b);
        integer i;
        host_oe = 4'b0001;
        for (i = 7; i >= 0; i = i - 1) begin
            SCLK_IN = 1'b0; host_io[0] = b[i]; wclk(half);
            SCLK_IN = 1'b1; wclk(half);
        end
    endtask

    task automatic tx_byte4(input [7:0] b);
        host_oe = 4'hF;
        SCLK_IN = 1'b0; host_io = b[7:4]; wclk(half);
        SCLK_IN = 1'b1; wclk(half);
        SCLK_IN = 1'b0; host_io = b[3:0]; wclk(half);
        SCLK_IN = 1'b1; wclk(half);
    endtask

    task automatic dummy_cycles(input integer n);
        integer i;
        host_oe = 4'h0;
        for (i = 0; i < n; i = i + 1) sclk_cycle();
    endtask

    // sample just before each rising edge
    task automatic rx_byte1(output [7:0] b);
        integer i;
        reg [7:0] t;
        host_oe = 4'h0;
        t = 8'h00;
        for (i = 7; i >= 0; i = i - 1) begin
            SCLK_IN = 1'b0; wclk(half);
            t = {t[6:0], pad_io[1]};
            SCLK_IN = 1'b1; wclk(half);
        end
        b = t;
    endtask

    task automatic rx_byte4(output [7:0] b);
        reg [3:0] hi, lo;
        host_oe = 4'h0;
        SCLK_IN = 1'b0; wclk(half); hi = pad_io;
        SCLK_IN = 1'b1; wclk(half);
        SCLK_IN = 1'b0; wclk(half); lo = pad_io;
        SCLK_IN = 1'b1; wclk(half);
        b = {hi, lo};
    endtask

    task automatic wr_csr(input [7:0] addr, input [7:0] data);
        cs_begin(); tx_byte1(8'h02); tx_byte1(addr); tx_byte1(data); cs_end();
    endtask

    task automatic wr_csr32(input [7:0] addr, input [31:0] data);
        cs_begin(); tx_byte1(8'h02); tx_byte1(addr);
        tx_byte1(data[7:0]); tx_byte1(data[15:8]); tx_byte1(data[23:16]); tx_byte1(data[31:24]);
        cs_end();
    endtask

    task automatic rd_csr(input [7:0] addr, input integer n, output [31:0] val);
        integer i; reg [7:0] b;
        half = RD_HALF;
        val = 0;
        cs_begin(); tx_byte1(8'h0B); tx_byte1(addr); dummy_cycles(8);
        for (i = 0; i < n; i = i + 1) begin rx_byte1(b); val[i*8 +: 8] = b; end
        cs_end();
        half = stream_half;
    endtask

    task automatic cmd_only(input [7:0] c);
        cs_begin(); tx_byte1(c); cs_end();
    endtask

    // ---------------------------------------------------------------- data
    reg [7:0]  expected [0:NPIX-1];
    reg [7:0]  got [0:NPIX-1];
    reg [7:0]  stream [0:TOTAL-1];
    reg [15:0] href [0:255];

    integer errors = 0;
    integer hrdy_waits;
    integer seed = 12345;

    task automatic stream_frame(input integer from, input integer to);
        integer i;
        cs_begin(); tx_byte1(8'h32);
        for (i = from; i < to; i = i + 1) begin
            if (!HRDY) begin
                hrdy_waits = hrdy_waits + 1;
                while (!HRDY) @(negedge clk);
            end
            tx_byte4(stream[i]);
        end
        cs_end();
    endtask

    task automatic run_image(input integer img, input bit split);
        integer p, len, i, mism, nfr;
        reg [7:0] rb;
        longint c0, c_stream_end, c_done, c_end;
        reg [31:0] st;
        hrdy_waits = 0;
        stream_half = half;
        c0 = cyc;
        cmd_only(8'h31);                                 // START
        if (!split) begin
            stream_frame(0, TOTAL);
            nfr = 1;
        end else begin
            p = 0; nfr = 0;
            while (p < TOTAL) begin
                len = 1 + ($urandom(seed) % 6000); seed = seed + 1;
                if (p + len > TOTAL) len = TOTAL - p;
                stream_frame(p, p + len);
                p = p + len; nfr = nfr + 1;
                if ($urandom(seed) % 4 == 0) wclk($urandom(seed) % 200);
                seed = seed + 1;
            end
        end
        c_stream_end = cyc;
        while (!HRDY) @(negedge clk);
        c_done = cyc;
        rd_csr(8'h02, 1, st);
        if (st[1:0] !== 2'b10 || st[4:3] !== 2'b00) begin
            $display("FAIL: image %0d STATUS=%02x (expect done=1 busy=0 no errors)", img, st[7:0]);
            errors = errors + 1;
        end
        rd_csr(8'h03, 3, st);
        if (st[19:0] !== TOTAL) begin
            $display("FAIL: stream byte count %0d", st[19:0]); errors = errors + 1;
        end
        half = RD_HALF;
        cs_begin(); tx_byte1(8'h6B);
        tx_byte4(8'h00); tx_byte4(8'h00);
        dummy_cycles(4);
        for (i = 0; i < NPIX; i = i + 1) begin rx_byte4(rb); got[i] = rb; end
        cs_end();
        half = stream_half;
        c_end = cyc;
        mism = 0;
        for (i = 0; i < NPIX; i = i + 1)
            if (got[i] !== expected[i]) begin
                mism = mism + 1;
                if (mism <= 8) $display("  pix %0d: got %02x exp %02x", i, got[i], expected[i]);
            end
        if (mism) errors = errors + 1;
        $display("IMAGE %0d (stream SCLK=clk/%0d, %0d frame(s)): %0d/%0d pixels bit-exact, %0d HRDY waits",
                 img, 2*stream_half, nfr, NPIX - mism, NPIX, hrdy_waits);
        $display("  cycles: START+stream %0d, last byte->DONE %0d, readback %0d, TOTAL %0d clk = %0.3f ms @25 MHz",
                 c_stream_end - c0, c_done - c_stream_end, c_end - c_done, c_end - c0,
                 (c_end - c0) * TCLK_NS * 1.0e-6);
    endtask

    task automatic check_csrs;
        reg [31:0] v;
        rd_csr(8'h00, 1, v); if (v[7:0] !== 8'hF6) begin $display("FAIL: ID %02x", v[7:0]); errors++; end
        rd_csr(8'h01, 1, v); if (v[7:0] !== 8'h04) begin $display("FAIL: CTRL %02x", v[7:0]); errors++; end
        rd_csr(8'h02, 1, v); if (v[7:0] !== 8'h04) begin $display("FAIL: STATUS %02x", v[7:0]); errors++; end
        rd_csr(8'h10, 4, v); if (v !== 32'd0)       begin $display("FAIL: 0x10 not 0 (%08x)", v); errors++; end
        wr_csr(8'h01, 8'h06);
        rd_csr(8'h01, 1, v); if (v[7:0] !== 8'h06) begin $display("FAIL: CTRL rw %02x", v[7:0]); errors++; end
        wr_csr(8'h01, 8'h04);
        cmd_only(8'hA5);
        rd_csr(8'h02, 1, v); if (v[3] !== 1'b1) begin $display("FAIL: err_cmd not set (%02x)", v[7:0]); errors++; end
        $display("CSR checks done (ID 0xF6, CTRL, STATUS, unmapped 0x10, CTRL rw, err_cmd)");
    endtask

    // FP16 activation pair p (0: P0 = GEN_ACT[0..1], 1: P1 = GEN_ACT[2..3]) vs a memh
    function automatic [15:0] act_word(input integer p, input integer i);
`ifdef GLS
        if (p == 0) act_word = {dut.\GEN_ACT[1].u_sram.u_sram .mem[i], dut.\GEN_ACT[0].u_sram.u_sram .mem[i]};
        else        act_word = {dut.\GEN_ACT[3].u_sram.u_sram .mem[i], dut.\GEN_ACT[2].u_sram.u_sram .mem[i]};
`else
        if (p == 0) act_word = {dut.GEN_ACT[1].u_sram.u_sram.mem[i], dut.GEN_ACT[0].u_sram.u_sram.mem[i]};
        else        act_word = {dut.GEN_ACT[3].u_sram.u_sram.mem[i], dut.GEN_ACT[2].u_sram.u_sram.mem[i]};
`endif
    endfunction

    task automatic check_act(input string f, input integer p, input string name);
        integer i, e;
        $readmemh(f, href);
        e = 0;
        for (i = 0; i < 256; i = i + 1) if (act_word(p, i) !== href[i]) e++;
        $display("%s activations (FP16) in pair P%0d: %0d/256 match", name, p, 256 - e);
        if (e) errors++;
    endtask

    string fn, exp_fn, src_fn, dir;
    integer nimg, i, do_split, do_abort;

    initial begin
        if (!$value$plusargs("STREAM_SRC=%s", src_fn)) src_fn = "sim/results/fp16/mnist/seed_0/stream.memh";
        if (!$value$plusargs("EXPECTED=%s", exp_fn)) begin
            dir = src_fn.substr(0, src_fn.len() - 12);          // strip "stream.memh"
            exp_fn = {dir, "expected_pix.memh"};
        end
        for (i = 0; i < NPIX; i = i + 1) expected[i] = 8'hxx;
        $readmemh(exp_fn, expected);
        if ((^expected[NPIX-1]) === 1'bx) begin $display("FAIL: %s: fewer than %0d pixels", exp_fn, NPIX); $finish; end
        stream[TOTAL-1] = 8'hxx;
        $readmemh(src_fn, stream);
        if ((^stream[TOTAL-1]) === 1'bx) begin $display("FAIL: %s: fewer than %0d bytes", src_fn, TOTAL); $finish; end
        $display("stream %s, expected %s", src_fn, exp_fn);
        if (!$value$plusargs("HALF=%d", half)) half = 2;
        stream_half = half;
        if (!$value$plusargs("IMAGES=%d", nimg)) nimg = 1;
        if (!$value$plusargs("SPLIT=%d", do_split)) do_split = 0;

        wclk(5);
        rst_n = 1'b1;
        wclk(5);

        check_csrs();

        if ($value$plusargs("ABORT=%d", do_abort) && do_abort) begin
            cmd_only(8'h31);
            stream_frame(0, 100037);
            $display("ABORT: abandoned an image after 100037 stream bytes (mid L2), restarting");
        end

        for (i = 1; i <= nimg; i = i + 1)
            run_image(i, (i >= 2) || (do_split != 0));

        if ($value$plusargs("H0=%s", fn)) check_act(fn, 1, "h0");
        if ($value$plusargs("H2=%s", fn)) check_act(fn, 0, "h2");
        if ($value$plusargs("ACTUAL_MEMH=%s", fn)) begin
            $writememh(fn, got);
            $display("read-back pixels written to %s", fn);
        end

        if (contention) begin $display("FAIL: %0d cycles of IO pad contention", contention); errors++; end
        if (errors == 0) $display("PASS: dla_fp16_chip -- %0d image(s), all 784 pixels bit-exact vs %s", nimg, exp_fn);
        else             $display("FAIL: dla_fp16_chip -- %0d error(s)", errors);
        $finish;
    end

endmodule
