// qspi_host_sdf.vh -- the src_int8/tb/chip/qspi_host.svh host in Verilog-2001 (for CVC), with the
// pad timing of the signoff SDC (src_int8/flow/sdc/base.sdc: set_input_delay / set_output_delay =
// 20 % of the clock period, both min and max):
//   * every host pad change happens TIN after a rising clk edge (the "tick"), not on the falling
//     edge as in the zero-delay TB;
//   * read data is sampled TCLK - TOUT after the edge that launched it (the latest point the SDC
//     allows), i.e. in the same clk cycle as in the zero-delay TB; io_mon.vh checks that no chip
//     output changes inside the last TOUT of any cycle;
//   * HRDY is used one cycle later than in the zero-delay TB (sampled TCLK - TOUT after the edge,
//     acted on at the next tick), so HRDY waits can take one more clk.
// Needs in scope: clk, SCLK_IN, CS_N_IN, host_io, host_oe, pad_io, hrdy_s, TIN, TSMP.

integer half;
initial half = 2;
localparam RD_HALF = 4;

task wclk(input integer n);
    begin
        repeat (n) @(posedge clk);
        #(TIN);
    end
endtask

task cs_begin;
    begin CS_N_IN = 1'b0; SCLK_IN = 1'b0; wclk(half); end
endtask

task cs_end;
    begin
        wclk(half);
        host_oe = 4'h0;
        CS_N_IN = 1'b1;
        wclk(4);
    end
endtask

task sclk_cycle;
    begin
        SCLK_IN = 1'b0; wclk(half);
        SCLK_IN = 1'b1; wclk(half);
    end
endtask

task tx_byte1(input [7:0] b);
    integer i;
    begin
        host_oe = 4'b0001;
        for (i = 7; i >= 0; i = i - 1) begin
            SCLK_IN = 1'b0; host_io[0] = b[i]; wclk(half);
            SCLK_IN = 1'b1; wclk(half);
        end
    end
endtask

task tx_byte4(input [7:0] b);
    begin
        host_oe = 4'hF;
        SCLK_IN = 1'b0; host_io = b[7:4]; wclk(half);
        SCLK_IN = 1'b1; wclk(half);
        SCLK_IN = 1'b0; host_io = b[3:0]; wclk(half);
        SCLK_IN = 1'b1; wclk(half);
    end
endtask

task dummy_cycles(input integer n);
    integer i;
    begin
        host_oe = 4'h0;
        for (i = 0; i < n; i = i + 1) sclk_cycle;
    end
endtask

// the zero-delay host samples, then raises SCLK, in the same tick; here SCLK rises at the tick
// and the sample is taken TSMP later in the same cycle (the chip sees SCLK only at the next edge)
task rx_byte1(output [7:0] b);
    integer i;
    reg [7:0] t;
    begin
        host_oe = 4'h0;
        t = 8'h00;
        for (i = 7; i >= 0; i = i - 1) begin
            SCLK_IN = 1'b0; wclk(half);
            SCLK_IN = 1'b1; #(TSMP); t = {t[6:0], pad_io[1]};
            wclk(half);
        end
        b = t;
    end
endtask

task rx_byte4(output [7:0] b);
    reg [3:0] hi, lo;
    begin
        host_oe = 4'h0;
        SCLK_IN = 1'b0; wclk(half);
        SCLK_IN = 1'b1; #(TSMP); hi = pad_io;
        wclk(half);
        SCLK_IN = 1'b0; wclk(half);
        SCLK_IN = 1'b1; #(TSMP); lo = pad_io;
        wclk(half);
        b = {hi, lo};
    end
endtask

task cmd_only(input [7:0] c);
    begin cs_begin; tx_byte1(c); cs_end; end
endtask

task wr_csr(input [7:0] addr, input [7:0] data);
    begin cs_begin; tx_byte1(8'h02); tx_byte1(addr); tx_byte1(data); cs_end; end
endtask

// n bytes (<= 4) from consecutive CSRs, little endian into val
task rd_csr(input [7:0] addr, input integer n, output [31:0] val);
    integer i, h;
    reg [7:0] b;
    begin
        h = half; half = RD_HALF;
        val = 0;
        cs_begin; tx_byte1(8'h0B); tx_byte1(addr); dummy_cycles(8);
        for (i = 0; i < n; i = i + 1) begin rx_byte1(b); val[i*8 +: 8] = b; end
        cs_end;
        half = h;
    end
endtask

task wait_hrdy;
    begin
        while (!hrdy_s) wclk(1);
    end
endtask

// one STREAM_Q frame of the bytes [from, to) of `sbyte` (HRDY checked before every byte)
task stream_frame(input integer from, input integer to, output integer waits);
    integer i;
    begin
        waits = 0;
        cs_begin; tx_byte1(8'h32);
        for (i = from; i < to; i = i + 1) begin
            if (!hrdy_s) begin waits = waits + 1; wait_hrdy; end
            tx_byte4(sbyte(i));
        end
        cs_end;
    end
endtask

// RD_MEM_Q of n bytes from memory byte address addr into rbuf[0..n-1]
task rd_mem_q(input [15:0] addr, input integer n);
    integer i, h;
    reg [7:0] b;
    begin
        h = half; half = RD_HALF;
        cs_begin; tx_byte1(8'h6B);
        tx_byte4(addr[15:8]); tx_byte4(addr[7:0]);
        dummy_cycles(4);
        for (i = 0; i < n; i = i + 1) begin rx_byte4(b); rbuf[i] = b; end
        cs_end;
        half = h;
    end
endtask
