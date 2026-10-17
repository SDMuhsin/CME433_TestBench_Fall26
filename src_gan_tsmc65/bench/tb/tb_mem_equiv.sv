`timescale 1ns / 1ps
// Random equivalence of the 65 nm latch RF (gan65_latch_rf, ce = 1, as in mem/dla_sram_1rw_256x8.v)
// with the flip-flop behaviour of mem/dla_sram_1rw_256x8_sim.v (modelled here): registered read
// every clock, read-before-write.  Inputs change at negedge like the chip's posedge logic outputs.
module tb_mem_equiv;
    reg clk = 0;
    always #5 clk = ~clk;
    reg        we = 0;
    reg  [7:0] addr = 0, wdata = 0;
    wire [7:0] q_rf;
    reg  [7:0] mem [0:255];
    reg  [7:0] q_ref;
    integer i, errors = 0, seed = 1, valid = 0;

    gan65_latch_rf #(.WIDTH(8), .AW(8)) dut (.clk(clk), .ce(1'b1), .we(we), .addr(addr), .wdata(wdata), .rdata(q_rf));

    always @(posedge clk) begin
        q_ref <= mem[addr];
        if (we) mem[addr] <= wdata;
    end

    initial begin
        // fill every word first so both models start defined
        for (i = 0; i < 256; i = i + 1) begin
            @(negedge clk); we = 1; addr = i; wdata = $urandom(seed);
        end
        @(negedge clk); we = 0; valid = 1;
        for (i = 0; i < 200000; i = i + 1) begin
            @(negedge clk);
            if (q_rf !== q_ref) begin
                errors = errors + 1;
                if (errors <= 5) $display("cycle %0d: rf %02x ref %02x", i, q_rf, q_ref);
            end
            we    = $urandom(seed) % 2;
            addr  = ($urandom(seed) % 4 == 0) ? addr : $urandom(seed) % 16 + (($urandom(seed) % 2) ? 240 : 0);
            wdata = $urandom(seed);
        end
        if (errors == 0) $display("PASS: latch RF == flip-flop model over 200000 random cycles");
        else             $display("FAIL: %0d mismatching cycles", errors);
        $finish;
    end
endmodule
