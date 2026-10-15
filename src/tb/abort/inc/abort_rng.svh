// abort_rng.svh -- seeded xorshift32 PRNG (same sequence in iverilog and Verilator).

reg [31:0] rng_s = 32'h1;

task automatic rng_seed(input integer s);
    rng_s = (s == 0) ? 32'h9E3779B9 : s;
endtask

function automatic [31:0] rng_next;
    reg [31:0] x;
    x = rng_s;
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    rng_s = x;
    rng_next = x;
endfunction

// uniform integer in [lo, hi]
function automatic integer rng(input integer lo, input integer hi);
    reg [31:0] r;
    r = rng_next();
    rng = lo + (r % (hi - lo + 1));
endfunction
