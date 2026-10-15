// sram_mon.vh -- SRAM access counter for the power cross-check (included in the TB module).
// Counts, per macro, the rising CLK edges with CEN = 0 as reads (GWEN = 1) or writes (GWEN = 0 and
// some WEN bit 0) -- the `when` cases of the macro Liberty internal_power on CLK -- while
// sram_cnt_en is 1 (the VCD window).  Hierarchical references into the routed netlist (instance
// names after src_int8/flow/sdf_gls/sdf/legal_netlist.py).  The 11 blocks are written out (no
// generate: hierarchical names cannot be indexed in Verilog-2001).  Index: 0..8 = HMEM
// u_h.GEN_H[0..8], 9 = BMEM u_b.u_even, 10 = BMEM u_b.u_odd.
// Needs in scope: sram_cnt_en.

integer sram_rd [0:10], sram_wr [0:10];
integer sram_i;
initial for (sram_i = 0; sram_i < 11; sram_i = sram_i + 1) begin sram_rd[sram_i] = 0; sram_wr[sram_i] = 0; end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_0__u_sram_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_0__u_sram_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_0__u_sram_u_sram.GWEN === 1'b1) sram_rd[0] = sram_rd[0] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_0__u_sram_u_sram.WEN)) sram_wr[0] = sram_wr[0] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_1__u_sram_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_1__u_sram_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_1__u_sram_u_sram.GWEN === 1'b1) sram_rd[1] = sram_rd[1] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_1__u_sram_u_sram.WEN)) sram_wr[1] = sram_wr[1] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_2__u_sram_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_2__u_sram_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_2__u_sram_u_sram.GWEN === 1'b1) sram_rd[2] = sram_rd[2] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_2__u_sram_u_sram.WEN)) sram_wr[2] = sram_wr[2] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_3__u_sram_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_3__u_sram_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_3__u_sram_u_sram.GWEN === 1'b1) sram_rd[3] = sram_rd[3] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_3__u_sram_u_sram.WEN)) sram_wr[3] = sram_wr[3] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_4__u_sram_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_4__u_sram_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_4__u_sram_u_sram.GWEN === 1'b1) sram_rd[4] = sram_rd[4] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_4__u_sram_u_sram.WEN)) sram_wr[4] = sram_wr[4] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_5__u_sram_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_5__u_sram_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_5__u_sram_u_sram.GWEN === 1'b1) sram_rd[5] = sram_rd[5] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_5__u_sram_u_sram.WEN)) sram_wr[5] = sram_wr[5] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_6__u_sram_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_6__u_sram_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_6__u_sram_u_sram.GWEN === 1'b1) sram_rd[6] = sram_rd[6] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_6__u_sram_u_sram.WEN)) sram_wr[6] = sram_wr[6] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_7__u_sram_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_7__u_sram_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_7__u_sram_u_sram.GWEN === 1'b1) sram_rd[7] = sram_rd[7] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_7__u_sram_u_sram.WEN)) sram_wr[7] = sram_wr[7] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_8__u_sram_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_8__u_sram_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_8__u_sram_u_sram.GWEN === 1'b1) sram_rd[8] = sram_rd[8] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_h_GEN_H_8__u_sram_u_sram.WEN)) sram_wr[8] = sram_wr[8] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_b_u_even_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_b_u_even_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_b_u_even_u_sram.GWEN === 1'b1) sram_rd[9] = sram_rd[9] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_b_u_even_u_sram.WEN)) sram_wr[9] = sram_wr[9] + 1;
    end
always @(posedge tb_mq_chip_sdf.dut.u_core_u_mem_u_b_u_odd_u_sram.CLK)
    if (sram_cnt_en && tb_mq_chip_sdf.dut.u_core_u_mem_u_b_u_odd_u_sram.CEN === 1'b0) begin
        if (tb_mq_chip_sdf.dut.u_core_u_mem_u_b_u_odd_u_sram.GWEN === 1'b1) sram_rd[10] = sram_rd[10] + 1;
        else if (!(&tb_mq_chip_sdf.dut.u_core_u_mem_u_b_u_odd_u_sram.WEN)) sram_wr[10] = sram_wr[10] + 1;
    end
