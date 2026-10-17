# Common setup of every gan65 tool script (DC, Formality, PrimeTime): the shared 65 nm kit
# config and helpers of src_int8_tsmc65 ($MQ65: libraries per corner, area / timing summary
# procs, mq65.sdc), plus the gan65 RTL list and area breakdown.
source $::env(MQ65)/syn/common/libs.tcl
source $::env(MQ65)/syn/common/summary.tcl
source $::env(GAN65)/syn/common/rtl.tcl
source $::env(GAN65)/syn/common/area.tcl
