// gan65_chip file list (paths relative to src_gan_tsmc65/rtl).  Include dirs: seq/ and cfg/w<W>
// (W = 8 | 16, the datapath width).  pe/gan_mul.v is the approximate-multiplier swap point (bench/build.sh replaces it).
// mem/gan65_icg.v is the behavioural ICG; synthesis swaps it for the library-cell wrapper.
mem/gan65_icg.v
mem/gan65_latch_rf.v
mem/dla_sram_1rw_256x8.v
pe/gan_mul.v
pe/dla_pe.v
dla/dla_pe_array.v
dla/dla_a_buffer_bank.v
dla/dla_b_buffer_bank.v
dla/dla_c_buffer_bank.v
dla/dla_controller.v
dla/dla_engine_top.v
seq/e2e_tanh_rom.v
seq/e2e_requant.v
seq/e2e_word_asm.v
seq/e2e_seq.v
host/e2e_host_qspi.v
host/e2e_dbg_pack.v
host/e2e_csr.v
top/gan65_chip.v
