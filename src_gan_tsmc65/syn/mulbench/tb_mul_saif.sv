`timescale 1ns / 1ps
// Gate-level (SDF-annotated) testbench of mul_bench for power: one new {a, b} pair per clock
// from +STIM=<memh> (+COUNT=<n>, at most 65536), switching activity of dut over all n cycles
// as SAIF (+SAIF=<file>), p written per clock to +OUT=<file> (line k + 2 = product of pair k).
// Parameters N (width) and HALF (half clock period, ns) are set at compile time.
module tb_mul_saif;
    parameter N = 16;
    parameter real HALF = 1.25;
    reg clk = 1'b0;
    reg [N - 1:0] a = 0, b = 0;
    wire [2 * N - 1:0] p;
    mul_bench dut (.clk(clk), .a(a), .b(b), .p(p));
    always #(HALF) clk = ~clk;
    reg [2 * N - 1:0] mem [0:65535];
    string stim, saif, outf;
    integer count, fo, i;
    initial begin
        void'($value$plusargs("STIM=%s", stim));
        void'($value$plusargs("SAIF=%s", saif));
        void'($value$plusargs("OUT=%s", outf));
        void'($value$plusargs("COUNT=%d", count));
        $readmemh(stim, mem);
        fo = $fopen(outf, "w");
        $set_gate_level_monitoring("on");
        $set_toggle_region(tb_mul_saif.dut);
        repeat (4) @(negedge clk);
        $toggle_start;
        for (i = 0; i < count + 2; i = i + 1) begin
            @(negedge clk);
            $fwrite(fo, "%h\n", p);
            if (i < count) {a, b} = mem[i];
        end
        $toggle_stop;
        $toggle_report(saif, 1.0e-12, "tb_mul_saif.dut");
        $fclose(fo);
        $display("SAIF_DONE %0d vectors, %0d clk", count, count + 2);
        $finish;
    end
endmodule
