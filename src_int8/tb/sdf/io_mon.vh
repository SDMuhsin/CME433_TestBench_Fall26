// io_mon.vh -- output timing monitor for the SDF GLS (included in the TB module).
// The signoff SDC puts set_output_delay TOUT (20 % of the period) on every output: an output
// launched by a clk edge must be stable TOUT before the next edge.  This monitor records the last
// change of any chip output (`outs`, all 44 pad-control + 4 IO out/oe + HRDY bits) and at every
// rising clk edge after reset release:
//   * counts an output-timing violation if that change fell inside (edge - TOUT, edge];
//   * keeps the worst (latest) output settle time after the previous edge.
// Needs in scope: clk, rst_n, outs, TCLK, TOUT.

real    om_last, om_edge, om_worst;
integer om_viol;
initial begin om_last = 0.0; om_edge = 0.0; om_worst = 0.0; om_viol = 0; end

always @(outs) om_last = $realtime;

always @(posedge clk) begin
    if (rst_n === 1'b1 && om_edge > 0.0) begin
        if (om_last > $realtime - TOUT && om_last <= $realtime && om_last > om_edge) begin
            om_viol = om_viol + 1;
            if (om_viol <= 10)
                $display("IO-TIMING: output change at %0.3f ns, %0.3f ns before the clk edge at %0.3f (output delay %0.1f)",
                         om_last, $realtime - om_last, $realtime, TOUT);
        end
        if (om_last > om_edge && om_last - om_edge > om_worst) om_worst = om_last - om_edge;
    end
    om_edge = $realtime;
end
