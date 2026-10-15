// abort_pads.svh -- pad-level wiring of mq_chip for tb_mq_abort (same as tb_mq_chip):
// quad IO resolved with the host drivers, every pad control brought out on `nc` so the
// X monitor can check all chip outputs.  Needs clk, rst_n in scope.

reg SCLK_IN = 1'b0, CS_N_IN = 1'b1;
reg [3:0] host_io = 4'h0, host_oe = 4'h0;
wire [3:0] chip_out, chip_oe, pad_io;
wire HRDY;
wire [43:0] nc;                                 // pad controls (constants), X-checked

genvar gi;
generate
    for (gi = 0; gi < 4; gi = gi + 1) begin : G_PAD
        assign pad_io[gi] = chip_oe[gi] ? chip_out[gi] : (host_oe[gi] ? host_io[gi] : 1'b0);
    end
endgenerate

mq_chip dut (
    .clk(clk), .clk_PU(nc[0]), .clk_PD(nc[1]), .rst_n(rst_n), .rst_n_PU(nc[2]), .rst_n_PD(nc[3]),
    .SCLK_IN(SCLK_IN), .SCLK_OUT(nc[4]), .SCLK_OE(nc[5]), .SCLK_IE(nc[6]), .SCLK_CS(nc[7]),
    .SCLK_SL(nc[8]), .SCLK_PU(nc[9]), .SCLK_PD(nc[10]),
    .MOSI_IN(pad_io[0]), .MOSI_OUT(chip_out[0]), .MOSI_OE(chip_oe[0]), .MOSI_IE(nc[11]),
    .MOSI_CS(nc[12]), .MOSI_SL(nc[13]), .MOSI_PU(nc[14]), .MOSI_PD(nc[15]),
    .CS_N_IN(CS_N_IN), .CS_N_OUT(nc[16]), .CS_N_OE(nc[17]), .CS_N_IE(nc[18]), .CS_N_CS(nc[19]),
    .CS_N_SL(nc[20]), .CS_N_PU(nc[21]), .CS_N_PD(nc[22]),
    .MISO_IN(pad_io[1]), .MISO_OUT(chip_out[1]), .MISO_OE(chip_oe[1]), .MISO_IE(nc[23]),
    .MISO_CS(nc[24]), .MISO_SL(nc[25]), .MISO_PU(nc[26]), .MISO_PD(nc[27]),
    .busy_IN(pad_io[2]), .busy_OUT(chip_out[2]), .busy_OE(chip_oe[2]), .busy_IE(nc[28]),
    .busy_CS(nc[29]), .busy_SL(nc[30]), .busy_PU(nc[31]), .busy_PD(nc[32]),
    .done_IN(pad_io[3]), .done_OUT(chip_out[3]), .done_OE(chip_oe[3]), .done_IE(nc[33]),
    .done_CS(nc[34]), .done_SL(nc[35]), .done_PU(nc[36]), .done_PD(nc[37]),
    .wb_done_IN(1'b0), .wb_done_OUT(HRDY), .wb_done_OE(nc[38]), .wb_done_IE(nc[39]),
    .wb_done_CS(nc[40]), .wb_done_SL(nc[41]), .wb_done_PU(nc[42]), .wb_done_PD(nc[43]));
