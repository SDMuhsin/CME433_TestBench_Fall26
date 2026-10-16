// mq_chip sources, paths relative to src_int8/rtl; include dirs: nonlin/ seq/
// Simulation adds mem/gf180_sram_macro.v (behavioural macro model; black box under SYNTHESIS).
// nonlin/mq_nlu_rom.v + mq_nlu_defs.vh and seq/mq_ucode_rom.v + mq_ucode_defs.vh are generated.
int/mq_rsh.v
int/mq_mul24x17.v
int/mq_mul8.v
int/mq_sat.v
lane/mq_lane.v
lane/mq_wb.v
lane/mq_dp.v
nonlin/mq_nlu_addr.v
nonlin/mq_nlu_rom.v
nonlin/mq_nlu.v
seq/mq_ucode_rom.v
seq/mq_uop_dec.v
seq/mq_loop.v
seq/mq_agu.v
seq/mq_regfile.v
seq/mq_seq.v
mem/mq_sram_256x8.v
mem/mq_hmem.v
mem/mq_bmem.v
mem/mq_mem.v
mem/mq_mem_arb.v
io/mq_pad_sync.v
io/mq_host_qspi.v
io/mq_csr.v
io/mq_stream_fifo.v
top/mq_core.v
top/mq_chip.v
