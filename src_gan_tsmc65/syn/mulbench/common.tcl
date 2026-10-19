# Common setup of the multiplier-bench tool scripts (DC, Formality, PrimeTime / PrimePower): the
# shared 65 nm kit config and helpers of src_int8_tsmc65 ($MQ65), the bench RTL list.
# Environment: GAN65 MQ65 MB_N (operand width 8 | 16) MB_DESIGN (rtl/w<N>/<design>.v)
source $::env(MQ65)/syn/common/libs.tcl
source $::env(MQ65)/syn/common/summary.tcl
proc mb_dir {} { return $::env(GAN65)/syn/mulbench }
proc mb_rtl_files {} {
    return [list [mb_dir]/mul_bench.v [mb_dir]/rtl/w$::env(MB_N)/$::env(MB_DESIGN).v]
}
proc mb_define {} { return "MUL_N=$::env(MB_N)" }
