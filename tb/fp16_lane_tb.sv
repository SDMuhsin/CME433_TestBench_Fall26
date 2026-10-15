`timescale 1ns / 1ps
// fp16_lane_tb -- drives fp16_lane with the 1296 real neuron traces of one image
// (bias, then (w, x) in order) at random issue intervals >= 2 clk (the minimum
// the lane supports) and checks the final FP32 accumulator of every neuron.
// Vectors: scripts/gen_fp16_unit_vectors.py <dir>  ->  +VEC=<dir>/lane_vec.txt
module fp16_lane_tb;
    reg clk = 0, rst_n = 0, issue = 0, ld = 0;
    reg [15:0] w, x, bias;
    wire can_issue, idle; wire [31:0] acc;
    always #5 clk = ~clk;
    fp16_lane dut (.clk(clk), .rst_n(rst_n), .clear(1'b0), .issue(issue), .w(w), .x(x),
                   .ld_bias(ld), .bias(bias), .can_issue(can_issue), .idle(idle), .acc(acc));
    integer f, r, nn = 0, bad = 0, macs = 0, gap, seed = 7;
    reg [31:0] e;
    reg [15:0] v1, v2;
    string fn, tag;
    initial begin
        if (!$value$plusargs("VEC=%s", fn)) fn = "sim/results/fp16/unit/lane_vec.txt";
        f = $fopen(fn, "r");
        if (f == 0) begin $display("FAIL: cannot open %s", fn); $finish; end
        repeat (2) @(negedge clk); rst_n = 1;
        while (!$feof(f)) begin
            r = $fscanf(f, "%s", tag);
            if (r != 1) break;
            if (tag == "B") begin
                r = $fscanf(f, "%h\n", v1);
                while (!idle) @(negedge clk);
                bias = v1; ld = 1; @(negedge clk); ld = 0;
            end else if (tag == "W") begin
                r = $fscanf(f, "%h %h\n", v1, v2);
                w = v1; x = v2; issue = 1; @(negedge clk); issue = 0;
                w = 16'hxxxx; x = 16'hxxxx;                       // operands only valid with issue
                gap = 1 + ($urandom(seed) % 4 == 0 ? $urandom(seed) % 5 : 0); seed = seed + 1;
                repeat (gap) @(negedge clk);
                macs = macs + 1;
            end else begin
                r = $fscanf(f, "%h\n", e);
                while (!idle) @(negedge clk);
                nn = nn + 1;
                if (acc !== e) begin
                    bad = bad + 1;
                    if (bad <= 10) $display("MISMATCH neuron %0d acc=%h exp=%h", nn - 1, acc, e);
                end
            end
        end
        if (bad == 0 && nn == 1296) $display("PASS: fp16_lane_tb %0d neurons / %0d MACs bit-exact", nn, macs);
        else                        $display("FAIL: fp16_lane_tb %0d/%0d neuron mismatches", bad, nn);
        $finish;
    end
endmodule
