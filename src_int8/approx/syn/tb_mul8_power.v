`timescale 1ns / 1ps
// Standalone stimulus for one mq_mul8 (RTL or gate-level netlist): applies the vectors of
// +VEC=<file> (one "aabb" hex line each, 65,536 lines) one per +PERIOD=<ns> (default 10),
// prints a checksum of the outputs sampled at the end of each period
// (sum (i+1) * p_i mod 2^32, see src_int8/approx/act/vectors.py) and, under VCS, records the
// switching activity of the operation window as SAIF (+SAIF=<file>) for PrimePower.
// Gate level with timing: +SDF=<file> back-annotates the DC delays (glitches are counted).
module tb_mul8_power;
    localparam NV = 65536;
    reg  [15:0] vec [0:NV-1];
    reg  signed [7:0] a, b;
    wire signed [15:0] p;
    reg  [31:0] sum;
    real period;
    integer i;
    reg [1023:0] fvec, fsaif, fsdf;

    mq_mul8 dut (.a(a), .b(b), .p(p));

    initial begin
        if (!$value$plusargs("VEC=%s", fvec)) fvec = "vec.hex";
        if (!$value$plusargs("PERIOD=%f", period)) period = 10.0;
        $readmemh(fvec, vec);
`ifdef VCS
        if ($value$plusargs("SDF=%s", fsdf)) $sdf_annotate(fsdf, dut);
        if (!$value$plusargs("SAIF=%s", fsaif)) fsaif = "mq_mul8.saif";
        $set_gate_level_monitoring("on");
        $set_toggle_region(tb_mul8_power.dut);
`endif
        sum = 0;
        {a, b} = 16'h0000;
        #(period);
`ifdef VCS
        $toggle_start;
`endif
        for (i = 0; i < NV; i = i + 1) begin
            {a, b} = vec[i];
            #(period);
            sum = sum + (i + 1) * p;
        end
`ifdef VCS
        $toggle_stop;
        $toggle_report(fsaif, 1.0e-12, "tb_mul8_power.dut");
`endif
        $display("CHECKSUM %08h  vectors %0d  period %0.3f ns", sum, NV, period);
        $finish;
    end
endmodule
