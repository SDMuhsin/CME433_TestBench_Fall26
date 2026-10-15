// mb_chip sources (Phase 2b), paths relative to src/rtl; include dirs: nonlin/ seq/
// Simulation adds mem/gf180_sram_macro.v (behavioural macro model; black box under SYNTHESIS).
fpu/mb_fp16_mul.v
fpu/mb_fp16_to_fp32.v
fpu/mb_fp32_add.v
fpu/mb_fp32_wb.v
lane/mb_lane.v
nonlin/mb_nlu_addr.v
nonlin/mb_nlu_frac.v
nonlin/mb_nlu_rom.v
nonlin/mb_nlu.v
seq/mb_ucode_rom.v
seq/mb_uop_dec.v
seq/mb_loop.v
seq/mb_agu.v
seq/mb_regfile.v
seq/mb_seq.v
mem/mb_sram_256x8.v
mem/mb_mem.v
mem/mb_mem_arb.v
io/mb_pad_sync.v
io/mb_host_qspi.v
io/mb_csr.v
io/mb_stream_fifo.v
top/mb_core.v
top/mb_chip.v
