# Write the StarRC command file and layer map for the routed block (tclsh; LEF/DEF flow).
#   tclsh ext/star_cmd.tcl <pnr_dir> <out_dir>
# RC model: the kit's StarRC technology file exists for the typical corner only.
# Coupling capacitances are kept (SPEF with cross-coupling) for PrimeTime.
source $::env(MQ65)/site/site.tcl
lassign $argv pnr out
# layer map: LEF/DEF layer names -> StarRC technology-file layer names (site config)
set f [open $out/star.map w]
puts $f "conducting_layers"
foreach {l t} $::MQ65_STAR_COND { puts $f "$l $t" }
puts $f "via_layers"
foreach {l t} $::MQ65_STAR_VIA { puts $f "$l $t" }
close $f
set f [open $out/star_cmd w]
puts $f "BLOCK: mq_chip
LEF_FILE: $::MQ65_LEF
TOP_DEF_FILE: $pnr/out/mq_chip.def
TCAD_GRD_FILE: $::MQ65_STAR_TECH
MAPPING_FILE: $out/star.map
OPERATING_TEMPERATURE: 25
EXTRACTION: RC
COUPLE_TO_GROUND: NO
REDUCTION: NO_EXTRA_LOOPS
NETS: *
SKIP_CELLS: *
NETLIST_FORMAT: SPEF
NETLIST_FILE: $out/mq_chip.star_typ.spef
SUMMARY_FILE: $out/star.sum
STAR_DIRECTORY: $out/star_work
NUM_CORES: 8"
close $f
