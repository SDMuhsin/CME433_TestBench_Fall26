`timescale 1ns / 1ps
// Simulation-only mq_mul8 (exact product) that records its input stream for power analysis:
// one line "aabb" (hex a, b) per input change, to +MUL8_DUMP=<file>, stopping the simulation
// after +MUL8_MAX=<n> changes (default 200000). Used by act/dump_stream.sh.
module mq_mul8 (
    input  wire signed [7:0]  a,
    input  wire signed [7:0]  b,
    output wire signed [15:0] p
);
    assign p = a * b;
`ifndef SYNTHESIS
    integer fd, n = 0, nmax;
    reg [1023:0] fn;
    initial begin
        if (!$value$plusargs("MUL8_DUMP=%s", fn)) fn = "mul8_stream.hex";
        if (!$value$plusargs("MUL8_MAX=%d", nmax)) nmax = 200000;
        fd = $fopen(fn, "w");
    end
    always @(a or b) begin
        $fdisplay(fd, "%h%h", a, b);
        n = n + 1;
        if (n == nmax) begin $fclose(fd); $finish; end
    end
`endif
endmodule
