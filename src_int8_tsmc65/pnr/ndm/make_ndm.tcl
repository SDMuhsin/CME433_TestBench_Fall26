# Build the standard-cell reference library (NDM) for ICC2 with the library manager:
# cell LEF (frame views) + the ss / tt / ff timing libraries, on the kit techfile.
# Environment: MQ65, MQ65_OUT (output dir; writes $MQ65_OUT/mq65_std.ndm)
source $::env(MQ65)/syn/common/libs.tcl
set out $::env(MQ65_OUT)
create_workspace mq65_std -technology $::MQ65_TF -flow normal
read_lef $::MQ65_LEF
foreach c {ss tt ff} { read_db [mq65_db $c] }
check_workspace
commit_workspace -force -output $out/mq65_std.ndm
puts "NDM_OK $out/mq65_std.ndm"
exit
