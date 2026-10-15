`timescale 1ns / 1ps

// ============================================================================
// dla_e2e_chip_tb -- pad-level host model for the END-TO-END G300 GAN chip.
//
// The testbench is the external 3.3 V host: it only touches the 11 pad
// terminals of dla_e2e_chip (bidirectional IO[3:0] = MOSI/MISO/busy/done pads
// are resolved here, with a contention check), and
//   1. checks ID / CTRL / the six requant-multiplier reset values over RD_CSR,
//   2. exercises the raw DLA debug path (DBG_WR_A/B, DBG_START, DBG_RD_C),
//   3. per image: START, STREAM_Q of zq + all weights/biases (283,984 B, built
//      here from weights_vh/ + tb/data/g300_int8/g300_zq.memh in the exact
//      e2e stream layout), honouring HRDY before every byte, waits for HRDY /
//      STATUS.done, then RD_PIX_Q reads back the 784 pixels (SCLK = clk/8) and
//      compares them bit-exactly with tb/data/g300_int8/g300_int8_rtl.memh.
//
// Plusargs:
//   +HALF=<n>    stream SCLK half period in clk (2 -> SCLK = clk/4 [default], 4 -> clk/8)
//   +IMAGES=<n>  back-to-back images (default 1); images >= 2 split the stream
//                into random-length STREAM_Q frames with random host pauses
//   +SPLIT=1     also split image 1
//   +ABORT=1     before image 1: START, stream ~50 kB (mid-L2), then abandon it
//                (the next START must restart cleanly)
//   +STREAM_MEMH=<file>  optional: cross-check the TB-built stream against a file
//   +H2Q=<file>  optional: check the h2 activations left in B col0
//   +ACTUAL_MEMH=<file>  dump the 784 pixels read back from the chip (int8 = uint8 pixel ^ 0x80,
//                one hex byte per line, same format as the golden)
// Data-driven plusargs (defaults = the committed MNIST G300 test):
//   +WDIR=<dir>  dir holding G300_{0,2,4}_{weight,bias}.memh   (weights_vh/mnist_gan_mlp)
//   +ZQ=<file>   64 x int8 latent                              (tb/data/g300_int8/g300_zq.memh)
//   +EXPECTED=<file>  784 x int8 golden pixels                 (tb/data/g300_int8/g300_int8_rtl.memh)
//   +STREAM_SRC=<file>  stream this prebuilt 283,984-B STREAM_Q payload instead of
//                building it from WDIR/ZQ (scripts/gen_e2e_stream.py writes one)
//   +CSR_MEMH=<file>  24 bytes = MA0,MB0,MA2,MB2,MW4,MB4 (32-bit LE, CSR 0x10..0x27);
//                written over the host protocol (WR_CSR) and read back before the
//                first image.  Without it the chip runs on the MNIST reset values.
// `define GLS: flat-netlist hierarchical name for the +H2Q check (scripts/run_e2e_gls.sh).
// Clock is 25 MHz (40 ns) so the reported times are real-time at the target.
// Run from the repo root (relative $readmemh paths).
// ============================================================================
module dla_e2e_chip_tb;
    localparam int NPIX = 784;
    localparam int TOTAL = 283984;
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

    dla_e2e_chip dut (
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
    reg [7:0] w0 [0:256*64-1];
    reg [7:0] w2 [0:256*256-1];
    reg [7:0] w4 [0:784*256-1];
    reg [7:0] b0 [0:255];
    reg [7:0] b2 [0:255];
    reg [7:0] b4 [0:783];
    reg [7:0] zq [0:63];
    reg [7:0] expected [0:NPIX-1];
    reg [7:0] got [0:NPIX-1];
    reg [7:0] stream [0:TOTAL-1];
    reg [7:0] ref_stream [0:TOTAL-1];
    reg [7:0] h2q [0:255];

    task automatic build_stream;
        integer p, t, r, k;
        p = 0;
        for (k = 0; k < 64; k = k + 1) begin stream[p] = zq[k]; p = p + 1; end
        for (t = 0; t < 64; t = t + 1) begin
            for (r = 0; r < 4; r = r + 1) begin stream[p] = b0[4*t+r]; p = p + 1; end
            for (r = 0; r < 4; r = r + 1) for (k = 0; k < 64; k = k + 1) begin stream[p] = w0[(4*t+r)*64 + k]; p = p + 1; end
        end
        for (t = 0; t < 64; t = t + 1) begin
            for (r = 0; r < 4; r = r + 1) begin stream[p] = b2[4*t+r]; p = p + 1; end
            for (r = 0; r < 4; r = r + 1) for (k = 0; k < 256; k = k + 1) begin stream[p] = w2[(4*t+r)*256 + k]; p = p + 1; end
        end
        for (t = 0; t < 196; t = t + 1) begin
            for (r = 0; r < 4; r = r + 1) begin stream[p] = b4[4*t+r]; p = p + 1; end
            for (r = 0; r < 4; r = r + 1) for (k = 0; k < 256; k = k + 1) begin stream[p] = w4[(4*t+r)*256 + k]; p = p + 1; end
        end
        if (p != TOTAL) begin $display("FAIL: stream length %0d", p); $finish; end
    endtask

    // ---------------------------------------------------------------- image
    integer errors = 0;
    integer hrdy_waits, max_skid;
    integer seed = 12345;

    // stream bytes [from, to) in one STREAM_Q frame, HRDY checked before each byte
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
                len = 1 + ($urandom(seed) % 3000); seed = seed + 1;
                if (p + len > TOTAL) len = TOTAL - p;
                stream_frame(p, p + len);
                p = p + len; nfr = nfr + 1;
                if ($urandom(seed) % 4 == 0) wclk($urandom(seed) % 200);
                seed = seed + 1;
            end
        end
        c_stream_end = cyc;
        // wait for HRDY (= DONE after the last byte), then confirm via STATUS
        while (!HRDY) @(negedge clk);
        c_done = cyc;
        rd_csr(8'h02, 1, st);
        if (st[1:0] !== 2'b10 || st[4:3] !== 2'b00) begin
            $display("FAIL: image %0d STATUS=%02x (expect done=1 busy=0 no errors)", img, st[7:0]);
            errors = errors + 1;
        end
        rd_csr(8'h03, 3, st);
        if (st[18:0] !== TOTAL) begin
            $display("FAIL: stream byte count %0d", st[18:0]); errors = errors + 1;
        end
        // RD_PIX_Q 784 bytes from address 0 at SCLK = clk/8
        half = RD_HALF;
        cs_begin(); tx_byte1(8'h6B);
        tx_byte4(8'h00); tx_byte4(8'h00);                 // addr[15:0] quad
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

    // ---------------------------------------------------------------- tests
    // write the six requant multipliers from a 24-byte memh, then read them back
    reg [7:0] csr_bytes [0:23];
    task automatic load_csrs(input string f);
        integer j;
        reg [31:0] w, v;
        reg [7:0] ad;
        for (j = 0; j < 24; j = j + 1) csr_bytes[j] = 8'hxx;
        $readmemh(f, csr_bytes);
        for (j = 0; j < 6; j = j + 1) begin
            w = {csr_bytes[4*j+3], csr_bytes[4*j+2], csr_bytes[4*j+1], csr_bytes[4*j]};
            if ((^w) === 1'bx) begin $display("FAIL: %s: fewer than 24 bytes", f); $finish; end
            ad = 8'h10 + 4*j;
            wr_csr32(ad, w);
            rd_csr(ad, 4, v);
            if (v !== w) begin $display("FAIL: CSR 0x%02x readback %0d, wrote %0d", ad, v, w); errors++; end
            $display("CSR 0x%02x <= %0d (0x%08x)", ad, w, w);
        end
        $display("requant CSRs written from %s", f);
    endtask

    task automatic check_csrs;
        reg [31:0] v;
        rd_csr(8'h00, 1, v); if (v[7:0] !== 8'hE2) begin $display("FAIL: ID %02x", v[7:0]); errors++; end
        rd_csr(8'h01, 1, v); if (v[7:0] !== 8'h04) begin $display("FAIL: CTRL %02x", v[7:0]); errors++; end
        rd_csr(8'h02, 1, v); if (v[7:0] !== 8'h04) begin $display("FAIL: STATUS %02x", v[7:0]); errors++; end
        rd_csr(8'h10, 4, v); if (v !== 32'd1173)      begin $display("FAIL: MA0 %0d", v); errors++; end
        rd_csr(8'h14, 4, v); if (v !== 32'd93743)     begin $display("FAIL: MB0 %0d", v); errors++; end
        rd_csr(8'h18, 4, v); if (v !== 32'd1102)      begin $display("FAIL: MA2 %0d", v); errors++; end
        rd_csr(8'h1C, 4, v); if (v !== 32'd35580)     begin $display("FAIL: MB2 %0d", v); errors++; end
        rd_csr(8'h20, 4, v); if (v !== 32'd32731085)  begin $display("FAIL: MW4 %0d", v); errors++; end
        rd_csr(8'h24, 4, v); if (v !== 32'd437099189) begin $display("FAIL: MB4 %0d", v); errors++; end
        // write/readback, then restore
        wr_csr32(8'h18, 32'hDEADBEEF);
        rd_csr(8'h18, 4, v); if (v !== 32'hDEADBEEF) begin $display("FAIL: MA2 rw %08x", v); errors++; end
        wr_csr32(8'h18, 32'd1102);
        // unknown command -> STATUS.err_cmd
        cmd_only(8'hA5);
        rd_csr(8'h02, 1, v); if (v[3] !== 1'b1) begin $display("FAIL: err_cmd not set (%02x)", v[7:0]); errors++; end
        $display("CSR checks done (ID, CTRL, STATUS, 6 multiplier reset values, rw, err_cmd)");
    endtask

    // raw DLA: A rows = r+1 (all k), B col c = c+1 for k<8; k_last = 7 -> C[r][c] = 8(r+1)(c+1)
    task automatic check_debug;
        integer r, c, k, e;
        reg [7:0] b;
        reg [31:0] v;
        e = errors;
        cs_begin(); tx_byte1(8'h10); tx_byte1(8'h00); tx_byte1(8'h00);       // A, addr 0
        for (r = 0; r < 4; r = r + 1) for (k = 0; k < 256; k = k + 1) tx_byte1((k < 8) ? r + 1 : 8'h7F);
        cs_end();
        cs_begin(); tx_byte1(8'h11); tx_byte1(8'h00); tx_byte1(8'h00);       // B, addr 0 (k*4+c)
        for (k = 0; k < 8; k = k + 1) for (c = 0; c < 4; c = c + 1) tx_byte1((c == 3) ? 8'hFF : c + 1);
        cs_end();
        cs_begin(); tx_byte1(8'h12); tx_byte1(8'd7); cs_end();             // DBG_START k_last=7
        wclk(100);
        half = RD_HALF;
        cs_begin(); tx_byte1(8'h13); tx_byte1(8'h00); tx_byte1(8'h00); dummy_cycles(8);
        for (r = 0; r < 4; r = r + 1) for (c = 0; c < 4; c = c + 1) begin
            for (k = 0; k < 4; k = k + 1) begin rx_byte1(b); v[k*8 +: 8] = b; end
            if ($signed(v) !== ((c == 3) ? -8 * (r + 1) : 8 * (r + 1) * (c + 1))) begin
                $display("FAIL: DBG C[%0d][%0d] = %0d", r, c, $signed(v)); errors++;
            end
        end
        cs_end();
        half = stream_half;
        if (errors == e) $display("DEBUG path OK (DBG_WR_A/B, DBG_START k_last=7, DBG_RD_C 16 words)");
    endtask

    string fn, wdir, zq_fn, exp_fn;
    integer nimg, i, h2err;
    integer do_split;
    integer do_abort;

    initial begin
        if (!$value$plusargs("WDIR=%s", wdir)) wdir = "weights_vh/mnist_gan_mlp";
        if (!$value$plusargs("ZQ=%s", zq_fn)) zq_fn = "tb/data/g300_int8/g300_zq.memh";
        if (!$value$plusargs("EXPECTED=%s", exp_fn)) exp_fn = "tb/data/g300_int8/g300_int8_rtl.memh";
        for (i = 0; i < NPIX; i = i + 1) expected[i] = 8'hxx;
        $readmemh(exp_fn, expected);
        if ((^expected[NPIX-1]) === 1'bx) begin $display("FAIL: %s: fewer than %0d pixels", exp_fn, NPIX); $finish; end
        if ($value$plusargs("STREAM_SRC=%s", fn)) begin
            stream[TOTAL-1] = 8'hxx;
            $readmemh(fn, stream);
            if ((^stream[TOTAL-1]) === 1'bx) begin $display("FAIL: %s: fewer than %0d bytes", fn, TOTAL); $finish; end
            $display("stream source: %s", fn);
        end else begin
            $readmemh({wdir, "/G300_0_weight.memh"}, w0);
            $readmemh({wdir, "/G300_2_weight.memh"}, w2);
            $readmemh({wdir, "/G300_4_weight.memh"}, w4);
            $readmemh({wdir, "/G300_0_bias.memh"}, b0);
            $readmemh({wdir, "/G300_2_bias.memh"}, b2);
            $readmemh({wdir, "/G300_4_bias.memh"}, b4);
            $readmemh(zq_fn, zq);
            build_stream();
            if (wdir != "weights_vh/mnist_gan_mlp" || zq_fn != "tb/data/g300_int8/g300_zq.memh")
                $display("stream built from %s + %s", wdir, zq_fn);
        end
        if ($value$plusargs("STREAM_MEMH=%s", fn)) begin
            $readmemh(fn, ref_stream);
            for (i = 0; i < TOTAL; i = i + 1)
                if (ref_stream[i] !== stream[i]) begin
                    $display("FAIL: stream byte %0d differs from %s", i, fn); errors++; i = TOTAL;
                end
            $display("stream cross-check vs %s done", fn);
        end
        if (!$value$plusargs("HALF=%d", half)) half = 2;
        stream_half = half;
        if (!$value$plusargs("IMAGES=%d", nimg)) nimg = 1;
        if (!$value$plusargs("SPLIT=%d", do_split)) do_split = 0;

        wclk(5);
        rst_n = 1'b1;
        wclk(5);

        check_csrs();
        check_debug();
        if ($value$plusargs("CSR_MEMH=%s", fn)) load_csrs(fn);

        if ($value$plusargs("ABORT=%d", do_abort) && do_abort) begin
            cmd_only(8'h31);
            stream_frame(0, 50021);
            $display("ABORT: abandoned an image after 50021 stream bytes (mid L2), restarting");
        end

        for (i = 1; i <= nimg; i = i + 1)
            run_image(i, (i >= 2) || (do_split != 0));

        if ($value$plusargs("H2Q=%s", fn)) begin
            $readmemh(fn, h2q);
            h2err = 0;
            for (i = 0; i < 256; i = i + 1)
`ifdef GLS
                if (dut.\u_dla.u_b_buffer.GEN_SRAM.GEN_B_COLS[0].u_sram.u_sram .mem[i] !== h2q[i]) h2err++;
`else
                if (dut.u_dla.u_b_buffer.GEN_SRAM.GEN_B_COLS[0].u_sram.u_sram.mem[i] !== h2q[i]) h2err++;
`endif
            $display("h2 activations in B col0: %0d/256 match", 256 - h2err);
            if (h2err) errors++;
        end
        if ($value$plusargs("ACTUAL_MEMH=%s", fn)) begin
            $writememh(fn, got);
            $display("read-back pixels written to %s", fn);
        end

        if (contention) begin $display("FAIL: %0d cycles of IO pad contention", contention); errors++; end
        if (errors == 0) $display("PASS: dla_e2e_chip -- %0d image(s), all 784 pixels bit-exact vs %s", nimg, exp_fn);
        else             $display("FAIL: dla_e2e_chip -- %0d error(s)", errors);
        $finish;
    end

endmodule
