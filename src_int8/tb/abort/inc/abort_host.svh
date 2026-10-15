// abort_host.svh -- host-side abort machinery of tb_mq_abort (on top of tb/common/qspi_host.svh):
//   wait_hrdy_to    bounded HRDY wait (a hang is a FAIL, the run stops)
//   stream_k        one STREAM_Q frame, HRDY honoured, optional partial last byte, stops on kill
//   beat / frame    frames as SCLK beats: any command cut after n beats (CS_N deasserted mid-frame)
//                   or held before its last rising edge until a trigger ("armed": the CSR write /
//                   START then reaches the core ~5 clk after the trigger)
//   rstn injector   asserts rst_n asynchronously (sub-cycle offset) when a trigger fires while
//                   the host keeps working; the host abandons its frame (CS_N high, drivers off)
// Triggers: T_NOW (after `delay` clk) or "the sequencer activity is A" (cur_act() == A; see
// abort_mon.svh), optionally after the byte count reached `min_bytes`.

localparam integer HANG_CLK = 2000000;        // > 4 token steps (450k clk each)
longint scen_cyc0 = 0;

task automatic hang(input string what);
    $display("FAIL: [%0s] HANG: %0s (cycle %0d): STATUS busy %b done %b tok %b HRDY %b pc %0d bytes %0d",
             scen, what, cyc, dut.busy, dut.done, dut.tok, HRDY, `SEQ.pc, dut.byte_cnt);
    $display("FAIL: tb_mq_abort -- hang");
    $finish;
endtask

always @(negedge clk) if (mon_on && cyc - scen_cyc0 > 4 * HANG_CLK) hang("scenario watchdog");

task automatic wait_hrdy_to(input string what);
    longint c0;
    c0 = cyc;
    while (!HRDY) begin
        @(negedge clk);
        if (cyc - c0 > HANG_CLK) hang({"HRDY never rose: ", what});
    end
endtask

// ---------------------------------------------------------------- stream with kill / partial byte
bit kill = 1'b0;                                // set by the rst_n injector
bit h_quad = 1'b1;                              // host view of CTRL.quad_en (STREAM_Q mode)

// one SCLK beat; drive io (mask oe) during the low half
task automatic beat(input [3:0] io, input [3:0] oe);
    host_oe = oe; SCLK_IN = 1'b0; host_io = io; wclk(half);
    SCLK_IN = 1'b1; wclk(half);
endtask

task automatic stream_byte(input [7:0] b);
    integer j;
    if (h_quad) begin beat(b[7:4], 4'hF); beat(b[3:0], 4'hF); end
    else for (j = 7; j >= 0; j--) beat({3'b000, b[j]}, 4'h1);
endtask

// STREAM_Q frame of bytes [from, to); then `part` beats of byte `to` (partial byte, 0 = none).
// Returns early (frame abandoned) when kill is set.
task automatic stream_k(input integer from, input integer to, input integer part);
    integer i, j;
    reg [7:0] b;
    cs_begin(); tx_byte1(8'h32);
    i = from;
    while (i < to && !kill) begin
        if (!HRDY) wait_hrdy_to("stream");
        if (!kill) stream_byte(sbyte(i));
        i++;
    end
    if (part > 0 && !kill) begin
        b = sbyte(to);
        if (!HRDY) wait_hrdy_to("stream");
        for (j = 0; j < part; j++)
            if (h_quad) beat(j == 0 ? b[7:4] : b[3:0], 4'hF);
            else        beat({3'b000, b[7 - j]}, 4'h1);
    end
    cs_end();
endtask

// ---------------------------------------------------------------- frames as beats
localparam int F_CMD = 0, F_WR = 1, F_RD = 2, F_RDM = 3, F_RDMQ = 4;

// drive of beat n of a frame (cmd byte c, address a, write data w): {oe, io}
function automatic [7:0] frame_beat(input integer kind, input [7:0] c, input [15:0] a,
                                    input [7:0] w, input integer n);
    reg [3:0] io, oe;
    io = 4'h0; oe = 4'h0;
    if (n < 8) begin io = {3'b000, c[7 - n]}; oe = 4'h1; end
    else case (kind)
        F_WR:  if (n < 16) begin io = {3'b000, a[15 - n]}; oe = 4'h1; end
               else if (n < 24) begin io = {3'b000, w[23 - n]}; oe = 4'h1; end
        F_RD:  if (n < 16) begin io = {3'b000, a[15 - n]}; oe = 4'h1; end
        F_RDM: if (n < 24) begin io = {3'b000, a[23 - n]}; oe = 4'h1; end
        F_RDMQ: if (n < 12) begin io = a[4 * (11 - n) +: 4]; oe = 4'hF; end
        default: ;
    endcase
    frame_beat = {oe, io};
endfunction

function automatic bit frame_is_rd(input integer kind);
    frame_is_rd = (kind == F_RD || kind == F_RDM || kind == F_RDMQ);
endfunction

// the frame cut after n beats (CS_N deasserted mid-frame; read data discarded)
task automatic cut_frame(input integer kind, input [7:0] c, input [15:0] a, input [7:0] w,
                         input integer n);
    integer j, h;
    reg [7:0] fb;
    h = half;
    if (frame_is_rd(kind)) half = RD_HALF;
    cs_begin();
    for (j = 0; j < n; j++) begin fb = frame_beat(kind, c, a, w, j); beat(fb[3:0], fb[7:4]); end
    cs_end();
    half = h;
endtask

// trigger wait: T_NOW, or cur_act() == trig (timeout 20k clk), then `delay` clk
localparam int T_NOW = -1;
bit trig_late = 1'b0;                           // the trigger did not fire before its timeout

task automatic trig_wait(input integer trig, input integer delay, input integer min_bytes);
    longint c0;
    trig_late = 1'b0;
    c0 = cyc;
    while (dut.byte_cnt < min_bytes && dut.busy && cyc - c0 < HANG_CLK) @(negedge clk);
    if (trig != T_NOW) begin
        c0 = cyc;
        while (cur_act() != trig && cyc - c0 < 20000) @(negedge clk);
        if (cur_act() != trig) trig_late = 1'b1;
    end
    wclk(delay);
endtask

// a 1-bit write frame (WR_CSR addr, data) or command byte whose last rising SCLK edge waits
// for the trigger; the abort reaches the core ~5 clk later
task automatic armed_frame(input integer kind, input [7:0] c, input [7:0] a, input [7:0] w,
                           input integer trig, input integer delay, input integer min_bytes);
    integer j, n;
    reg [7:0] fb;
    n = (kind == F_WR) ? 24 : 8;
    cs_begin();
    for (j = 0; j < n - 1; j++) begin fb = frame_beat(kind, c, {8'h00, a}, w, j); beat(fb[3:0], fb[7:4]); end
    fb = frame_beat(kind, c, {8'h00, a}, w, n - 1);
    host_oe = fb[7:4]; SCLK_IN = 1'b0; host_io = fb[3:0]; wclk(half);
    trig_wait(trig, delay, min_bytes);
    land_arm = 1'b1;
    SCLK_IN = 1'b1; wclk(half);
    cs_end();
    wclk(4);
    land_arm = 1'b0;
endtask

// ---------------------------------------------------------------- rst_n injector
bit     inj_go = 1'b0, inj_done = 1'b0;
reg [3:0] oe_at_rst = 4'h0;                     // chip IO drivers just before the assertion
integer inj_trig = T_NOW, inj_delay = 0, inj_width = 1, inj_sub = 7, inj_min = 0;

initial forever begin
    wait (inj_go);
    trig_wait(inj_trig, inj_delay, inj_min);    // returns on a falling clk edge
    #(inj_sub);                                 // asynchronous assertion, inj_sub ns later (1..19)
    land_arm = 1'b1;
    oe_at_rst = chip_oe;
    rst_n = 1'b0;
    kill = 1'b1;
    CS_N_IN = 1'b1; SCLK_IN = 1'b0; host_oe = 4'h0;
    #1;
    if (chip_oe !== 4'h0) fail("IO drivers not released at rst_n assertion");
    land_arm = 1'b0;
    if (inj_width > 0) wclk(inj_width);         // deassertion on a falling edge (sync release)
    else #(5);                                  // sub-cycle pulse: 5 ns, asynchronous release
    rst_n = 1'b1;
    inj_go = 1'b0;
    inj_done = 1'b1;
end

// arm the injector; the caller then does host work and calls rstn_join()
task automatic rstn_arm(input integer trig, input integer delay, input integer min_bytes,
                        input integer width, input integer sub_ns);
    inj_trig = trig; inj_delay = delay; inj_min = min_bytes; inj_width = width;
    // sub-cycle pulses are released >= 5 ns before the next rising clk edge (host contract)
    inj_sub = (width == 0 && sub_ns > 9) ? 9 : (sub_ns < 1) ? 1 : (sub_ns > 19) ? 19 : sub_ns;
    inj_done = 1'b0; kill = 1'b0;
    inj_go = 1'b1;
endtask

task automatic rstn_join;
    longint c0;
    c0 = cyc;
    while (!inj_done) begin
        @(negedge clk);
        if (cyc - c0 > HANG_CLK) hang("rst_n injector never fired");
    end
    wclk(4);                                    // host: CS_N high >= 2 clk after reset release
    kill = 1'b0;
    h_quad = 1'b1;                              // CTRL reset value: quad_en = 1
endtask
