# PnR SDC for mq_chip (PNR_SDC_FILE): base.sdc over-constrained to max_transition 0.9 ns /
# max_capacitance 0.12 pF so resizer repair leaves headroom for routed (SPEF) parasitics and
# antenna diodes (same as src_int8/flow/sdc/pnr.sdc, FP16 mq_chip).
set ::mq_max_tran 0.9
set ::mq_max_cap 0.12
source [file join [file dirname [file normalize [info script]]] base.sdc]
