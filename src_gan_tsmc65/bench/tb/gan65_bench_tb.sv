`timescale 1ns / 1ps
`include "gan65_cfg.vh"

// ============================================================================
// gan65_bench_tb -- pad-level host model of gan65_chip for the image benchmark.
//
// The TB is the external host: it only drives sclk / cs_n / io[3:0] and reads
// io[3:0] / hrdy, using the protocol of docs/dla_e2e_chip.md (host tasks taken
// from tb/dla_e2e_chip_tb.sv).  After reset it writes the six requant CSRs,
// then for each latent of a batch: START, STREAM_Q of zq + all weights and
// biases (283,984 elements of DATA_W/8 bytes, little endian, = 283,984 B on the
// 8-bit chip; SCLK = clk/4, HRDY honoured before every byte), wait for
// HRDY, check STATUS, RD_PIX_Q the 784 pixels (SCLK = clk/8) and append them to
// the output file.  No pixel is checked here: the Python scorer compares the
// dump with the golden model, so the same TB serves approximate multipliers.
//
// Plusargs (all required except HALF):
//   +WDIR=<dir>      G300_{0,2,4}_{weight,bias}.memh (DATA_W-bit hex, row-major [out][in])
//   +CSR_MEMH=<f>    24 bytes MA0,MB0,MA2,MB2,MW4,MB4 (32-bit LE, CSR 0x10..0x27)
//   +ZQ_ALL=<f>      latents, 64 DATA_W-bit hex lines per image
//   +FIRST=<i> +COUNT=<n>   run images FIRST .. FIRST+COUNT-1 of ZQ_ALL
//   +OUT=<f>         pixel dump, 784 hex lines per image (int8 = uint8 pixel ^ 0x80)
// DATA_W = `GAN65_DATA_W from rtl/cfg/w<W>/gan65_cfg.vh on the include path.
//   +HALF=<n>        stream SCLK half period in clk (default 2 -> SCLK = clk/4)
// Exit: "DONE <n> images" on success, "FAIL: ..." on a protocol / status error.
// ============================================================================
module gan65_bench_tb;
    localparam int DW       = `GAN65_DATA_W;
    localparam int NB       = DW / 8;     // bytes per stream element
    localparam int NEL      = 283984;     // stream elements
    localparam int TOTAL    = NEL * NB;   // stream bytes
    localparam int NPIX     = 784;
    localparam int MAX_IMG  = 16384;
    localparam int RD_HALF  = 4;          // reads: SCLK = clk/8

    // clk half period in ns: 20 = the 25 MHz reference (cycle counts are what matter); the
    // gate-level run (sim/gls/run_gls.csh) sets the synthesis clock for realistic activity.
    parameter real CLK_HALF_NS = 20.0;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_HALF_NS) clk = ~clk;

    reg        sclk = 1'b0, cs_n = 1'b1;
    reg  [3:0] host_io = 4'h0, host_oe = 4'h0;
    wire [3:0] chip_out, chip_oe, pad_io;
    wire       HRDY;

    genvar gi;
    generate
        for (gi = 0; gi < 4; gi = gi + 1) begin : G_PAD
            assign pad_io[gi] = chip_oe[gi] ? chip_out[gi] : (host_oe[gi] ? host_io[gi] : 1'b0);
        end
    endgenerate

    gan65_chip dut (
        .clk(clk), .rst_n(rst_n), .sclk(sclk), .cs_n(cs_n),
        .io_in(pad_io), .io_out(chip_out), .io_oe(chip_oe), .hrdy(HRDY)
    );

    longint cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    integer half = 2;
    integer stream_half = 2;
    integer errors = 0;

    // ------------------------------------------------------------ host primitives
    task automatic wclk(input integer n);
        repeat (n) @(negedge clk);
    endtask

    task automatic cs_begin;
        cs_n = 1'b0; sclk = 1'b0; wclk(half);
    endtask

    task automatic cs_end;
        wclk(half);
        host_oe = 4'h0;
        cs_n = 1'b1;
        wclk(4);
    endtask

    task automatic sclk_cycle;
        sclk = 1'b0; wclk(half);
        sclk = 1'b1; wclk(half);
    endtask

    task automatic tx_byte1(input [7:0] b);
        integer i;
        host_oe = 4'b0001;
        for (i = 7; i >= 0; i = i - 1) begin
            sclk = 1'b0; host_io[0] = b[i]; wclk(half);
            sclk = 1'b1; wclk(half);
        end
    endtask

    task automatic tx_byte4(input [7:0] b);
        host_oe = 4'hF;
        sclk = 1'b0; host_io = b[7:4]; wclk(half);
        sclk = 1'b1; wclk(half);
        sclk = 1'b0; host_io = b[3:0]; wclk(half);
        sclk = 1'b1; wclk(half);
    endtask

    task automatic dummy_cycles(input integer n);
        integer i;
        host_oe = 4'h0;
        for (i = 0; i < n; i = i + 1) sclk_cycle();
    endtask

    task automatic rx_byte1(output [7:0] b);
        integer i;
        reg [7:0] t;
        host_oe = 4'h0;
        t = 8'h00;
        for (i = 7; i >= 0; i = i - 1) begin
            sclk = 1'b0; wclk(half);
            t = {t[6:0], pad_io[1]};
            sclk = 1'b1; wclk(half);
        end
        b = t;
    endtask

    task automatic rx_byte4(output [7:0] b);
        reg [3:0] hi, lo;
        host_oe = 4'h0;
        sclk = 1'b0; wclk(half); hi = pad_io;
        sclk = 1'b1; wclk(half);
        sclk = 1'b0; wclk(half); lo = pad_io;
        sclk = 1'b1; wclk(half);
        b = {hi, lo};
    endtask

    task automatic cmd_only(input [7:0] c);
        cs_begin(); tx_byte1(c); cs_end();
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

    // ------------------------------------------------------------ data
    reg [DW-1:0] w0 [0:256*64-1];
    reg [DW-1:0] w2 [0:256*256-1];
    reg [DW-1:0] w4 [0:784*256-1];
    reg [DW-1:0] b0 [0:255];
    reg [DW-1:0] b2 [0:255];
    reg [DW-1:0] b4 [0:783];
    reg [DW-1:0] zq_all [0:64*MAX_IMG-1];
    reg [7:0] stream [0:TOTAL-1];
    reg [7:0] csr_bytes [0:23];

    // stream layout: zq[64]; L0 64 x {4 bias, 4 x 64 W}; L2 64 x {4 bias, 4 x 256 W};
    // L4 196 x {4 bias, 4 x 256 W}, each element NB bytes, least significant first.
    // The weight part is built once, zq is patched per image.
    task automatic put_el(inout integer p, input [DW-1:0] v);
        integer j;
        for (j = 0; j < NB; j = j + 1) begin stream[p] = v[8*j +: 8]; p = p + 1; end
    endtask

    task automatic build_weight_stream;
        integer p, t, r, k;
        p = 64 * NB;
        for (t = 0; t < 64; t = t + 1) begin
            for (r = 0; r < 4; r = r + 1) put_el(p, b0[4*t+r]);
            for (r = 0; r < 4; r = r + 1) for (k = 0; k < 64; k = k + 1) put_el(p, w0[(4*t+r)*64 + k]);
        end
        for (t = 0; t < 64; t = t + 1) begin
            for (r = 0; r < 4; r = r + 1) put_el(p, b2[4*t+r]);
            for (r = 0; r < 4; r = r + 1) for (k = 0; k < 256; k = k + 1) put_el(p, w2[(4*t+r)*256 + k]);
        end
        for (t = 0; t < 196; t = t + 1) begin
            for (r = 0; r < 4; r = r + 1) put_el(p, b4[4*t+r]);
            for (r = 0; r < 4; r = r + 1) for (k = 0; k < 256; k = k + 1) put_el(p, w4[(4*t+r)*256 + k]);
        end
        if (p != TOTAL) begin $display("FAIL: stream length %0d", p); $finish; end
    endtask

    task automatic write_csrs;
        integer j;
        reg [31:0] w, v;
        reg [7:0] ad;
        for (j = 0; j < 6; j = j + 1) begin
            w  = {csr_bytes[4*j+3], csr_bytes[4*j+2], csr_bytes[4*j+1], csr_bytes[4*j]};
            ad = 8'h10 + 4*j;
            if ((^w) === 1'bx) begin $display("FAIL: CSR file has fewer than 24 bytes"); $finish; end
            wr_csr32(ad, w);
            rd_csr(ad, 4, v);
            if (v !== w) begin $display("FAIL: CSR 0x%02x readback %0d, wrote %0d", ad, v, w); $finish; end
        end
    endtask

    task automatic stream_all;
        integer i;
        cs_begin(); tx_byte1(8'h32);
        for (i = 0; i < TOTAL; i = i + 1) begin
            while (!HRDY) @(negedge clk);
            tx_byte4(stream[i]);
        end
        cs_end();
    endtask

    task automatic run_image(input integer img, input integer fd);
        integer i, p;
        reg [7:0] rb;
        reg [31:0] st;
        longint c0;
        p = 0;
        for (i = 0; i < 64; i = i + 1) put_el(p, zq_all[64*img + i]);
        c0 = cyc;
        cmd_only(8'h31);                                   // START
        stream_all();
        while (!HRDY) @(negedge clk);
        rd_csr(8'h02, 1, st);
        if (st[1:0] !== 2'b10 || st[4:3] !== 2'b00) begin
            $display("FAIL: image %0d STATUS=%02x (expect done=1 busy=0 no errors)", img, st[7:0]);
            errors = errors + 1;
        end
        half = RD_HALF;
        cs_begin(); tx_byte1(8'h6B);                       // RD_PIX_Q from pixel 0
        tx_byte4(8'h00); tx_byte4(8'h00);
        dummy_cycles(4);
        for (i = 0; i < NPIX; i = i + 1) begin rx_byte4(rb); $fdisplay(fd, "%02x", rb); end
        cs_end();
        half = stream_half;
        $display("IMAGE %0d %0d clk", img, cyc - c0);
    endtask

    // ------------------------------------------------------------ main
    string wdir, fn, out_fn;
    integer first, count, fd, n;

    initial begin
        if (!$value$plusargs("WDIR=%s", wdir))    begin $display("FAIL: +WDIR missing"); $finish; end
        if (!$value$plusargs("OUT=%s", out_fn))   begin $display("FAIL: +OUT missing"); $finish; end
        if (!$value$plusargs("FIRST=%d", first))  first = 0;
        if (!$value$plusargs("COUNT=%d", count))  count = 1;
        if (!$value$plusargs("HALF=%d", half))    half = 2;
        stream_half = half;
        $readmemh({wdir, "/G300_0_weight.memh"}, w0);
        $readmemh({wdir, "/G300_0_bias.memh"},   b0);
        $readmemh({wdir, "/G300_2_weight.memh"}, w2);
        $readmemh({wdir, "/G300_2_bias.memh"},   b2);
        $readmemh({wdir, "/G300_4_weight.memh"}, w4);
        $readmemh({wdir, "/G300_4_bias.memh"},   b4);
        if (!$value$plusargs("CSR_MEMH=%s", fn)) begin $display("FAIL: +CSR_MEMH missing"); $finish; end
        for (n = 0; n < 24; n = n + 1) csr_bytes[n] = 8'hxx;
        $readmemh(fn, csr_bytes);
        if (!$value$plusargs("ZQ_ALL=%s", fn))   begin $display("FAIL: +ZQ_ALL missing"); $finish; end
        $readmemh(fn, zq_all, 0, 64*(first+count)-1);
        build_weight_stream();

        repeat (10) @(negedge clk);
        rst_n = 1'b1;
        repeat (10) @(negedge clk);
        write_csrs();

        fd = $fopen(out_fn, "w");
        if (fd == 0) begin $display("FAIL: cannot open %s", out_fn); $finish; end
        for (n = first; n < first + count; n = n + 1) run_image(n, fd);
        $fclose(fd);
        if (errors == 0) $display("DONE %0d images", count);
        else             $display("FAIL: %0d status error(s)", errors);
        $finish;
    end
endmodule
