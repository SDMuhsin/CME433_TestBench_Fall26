// qspi_host.svh -- pad-level host bus-functional model for mb_chip (included in the TB module).
//
// Needs in scope: clk, SCLK_IN, CS_N_IN, host_io, host_oe, pad_io, HRDY.
// All host pad changes happen on the falling clk edge (no race with the chip's rising-edge
// synchronisers).  `half` = SCLK half period in clk: 2 (clk/4) for writes and streaming,
// RD_HALF = 4 (clk/8) for read phases.  Reads sample just before each rising SCLK edge.

integer half = 2;
localparam int RD_HALF = 4;

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

task automatic cmd_only(input [7:0] c);
    cs_begin(); tx_byte1(c); cs_end();
endtask

task automatic wr_csr(input [7:0] addr, input [7:0] data);
    cs_begin(); tx_byte1(8'h02); tx_byte1(addr); tx_byte1(data); cs_end();
endtask

// n bytes (<= 4) from consecutive CSRs, little endian into val
task automatic rd_csr(input [7:0] addr, input integer n, output [31:0] val);
    integer i, h;
    reg [7:0] b;
    h = half; half = RD_HALF;
    val = 0;
    cs_begin(); tx_byte1(8'h0B); tx_byte1(addr); dummy_cycles(8);
    for (i = 0; i < n; i = i + 1) begin rx_byte1(b); val[i*8 +: 8] = b; end
    cs_end();
    half = h;
endtask

task automatic wait_hrdy;
    while (!HRDY) @(negedge clk);
endtask

// one STREAM_Q frame of the bytes from[from, to) of `sbyte` (HRDY checked before every byte)
task automatic stream_frame(input integer from, input integer to, output integer waits);
    integer i;
    waits = 0;
    cs_begin(); tx_byte1(8'h32);
    for (i = from; i < to; i = i + 1) begin
        if (!HRDY) begin waits = waits + 1; wait_hrdy(); end
        tx_byte4(sbyte(i));
    end
    cs_end();
endtask

// RD_MEM_Q of n bytes from memory byte address addr into rbuf[0..n-1]
task automatic rd_mem_q(input [15:0] addr, input integer n);
    integer i, h;
    reg [7:0] b;
    h = half; half = RD_HALF;
    cs_begin(); tx_byte1(8'h6B);
    tx_byte4(addr[15:8]); tx_byte4(addr[7:0]);
    dummy_cycles(4);
    for (i = 0; i < n; i = i + 1) begin rx_byte4(b); rbuf[i] = b; end
    cs_end();
    half = h;
endtask
