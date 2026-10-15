// tb_report.svh -- shared vector-file open and PASS/FAIL reporting for the unit TBs.
// Use inside a module that declares: integer fd, n, bad; string vec.
task automatic open_vec(input string name);
    if (!$value$plusargs("VEC=%s", vec)) begin
        $display("FAIL %s: no +VEC=<file>", name); $finish;
    end
    fd = $fopen(vec, "r");
    if (fd == 0) begin $display("FAIL %s: cannot open %s", name, vec); $finish; end
    n = 0; bad = 0;
endtask

task automatic report(input string name);
    if (bad == 0 && n > 0) $display("PASS %s: %0d vectors bit-exact", name, n);
    else                   $display("FAIL %s: %0d/%0d mismatches", name, bad, n);
    $finish;
endtask
