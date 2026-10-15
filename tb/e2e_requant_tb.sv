`timescale 1ns / 1ps

// e2e_requant_tb -- unit test of the dla_e2e_chip requant unit (bias + requant +
// ReLU/sat or tanh threshold-ROM search) against the bit-true Python reference.
// Vectors: python3 scripts/gen_e2e_vectors.py <dir>  ->  <dir>/e2e_requant_vectors.memh
//   (1,296 golden G300 neuron tuples + corners + random).  Pass the file with
//   +VEC=<path>.  Prints "PASS: e2e_requant <n>/<n>".
module e2e_requant_tb;
    localparam int MAXV = 200000;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg         start = 0, mode = 0;
    reg  signed [23:0] acc = 0;
    reg  signed [7:0]  bias = 0;
    reg  [31:0] m_a = 0, m_b = 0;
    wire        busy, valid;
    wire [7:0]  q;

    e2e_requant dut (.clk(clk), .rst_n(rst_n), .clear(1'b0), .start(start), .mode_tanh(mode),
                     .acc(acc), .bias(bias), .m_a(m_a), .m_b(m_b),
                     .busy(busy), .valid(valid), .q(q));

    reg [111:0] vec [0:MAXV-1];
    string fn;
    integer n, i, errs, lat, max_lat;

    initial begin
        for (i = 0; i < MAXV; i = i + 1) vec[i] = 'x;
        if (!$value$plusargs("VEC=%s", fn)) fn = "e2e_requant_vectors.memh";
        $readmemh(fn, vec);
        n = 0; while (n < MAXV && vec[n][0] !== 1'bx) n = n + 1;
        if (n == 0) begin $display("FAIL: no vectors in %s", fn); $finish; end
        errs = 0; max_lat = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        for (i = 0; i < n; i = i + 1) begin
            {mode, acc, bias, m_a, m_b} = {vec[i][104], vec[i][103:80], vec[i][79:72], vec[i][71:40], vec[i][39:8]};
            start <= 1'b1;
            @(posedge clk);
            start <= 1'b0;
            lat = 1;
            while (!valid) begin @(posedge clk); lat = lat + 1; end
            if (lat > max_lat) max_lat = lat;
            if (q !== vec[i][7:0]) begin
                errs = errs + 1;
                if (errs <= 10)
                    $display("MISMATCH #%0d mode=%0d acc=%0d b=%0d ma=%0d mb=%0d : got %02x exp %02x",
                             i, mode, acc, bias, m_a, m_b, q, vec[i][7:0]);
            end
            @(posedge clk);
        end
        if (errs == 0) $display("PASS: e2e_requant %0d/%0d vectors bit-exact (max latency %0d clk)", n, n, max_lat);
        else           $display("FAIL: e2e_requant %0d/%0d mismatches", errs, n);
        $finish;
    end
endmodule
