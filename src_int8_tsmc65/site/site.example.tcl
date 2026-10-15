# Site config template for the mq65 flow. Copy to site/site.tcl (git-ignored) and replace
# every <PLACEHOLDER> with the values of your process kit. Sourced by syn/common/libs.tcl.
# Corners: ss = setup signoff (slow, hot), tt = typical / power, ff = hold (fast, cold).

set ::MQ65_KIT $::env(MQ65_KIT)

# ---- standard-cell timing libraries (.db)
set ::MQ65_LIBDIR <STDCELL_DB_DIR>
set ::MQ65_VLOG   <STDCELL_VERILOG_MODEL>
array set ::MQ65_CORNER_LIB {ss <STDCELL_LIB_SS> tt <STDCELL_LIB_TT> ff <STDCELL_LIB_FF>}
array set ::MQ65_CORNER_OC  {ss <OPCOND_SS> tt <OPCOND_TT> ff <OPCOND_FF>}
set ::MQ65_CORNER_DESC {ss (<OPCOND_SS>), min ff (<OPCOND_FF>)}
set ::MQ65_WLM_GROUP <WIRE_LOAD_SELECTION_GROUP>

# ---- physical (DC topographical mode)
set ::MQ65_MW     <MILKYWAY_DIR>
set ::MQ65_MW_REF <MILKYWAY_REFERENCE_LIB>
set ::MQ65_TF     <TECHFILE>
set ::MQ65_TLU    <RC_TECH_DIR>
set ::MQ65_TLU_MAP <RC_TECH_LAYER_MAP>
# RC setup for DC topographical mode: load the max (ss) / min (ff) RC model files and the
# layer map with the DC command for your kit's RC model format.
proc mq65_rc_setup {} {
    <RC_SETUP_CMD> <MAX_OPT> [mq65_tlu ss] <MIN_OPT> [mq65_tlu ff] <MAP_OPT> $::MQ65_TLU_MAP
}
array set ::MQ65_CORNER_TLU {
    ss <RC_TECH_FILE_WORST>
    tt <RC_TECH_FILE_TYPICAL>
    ff <RC_TECH_FILE_BEST>
}

# ---- reference cells
set ::MQ65_NAND2       <NAND2_X1_CELL>
set ::MQ65_ICG_PATTERN <ICG_CELL_GLOB>
set ::MQ65_DRV_IN      {<INPUT_DRIVER_CELL> <OUTPUT_PIN>}
set ::MQ65_DRV_CLK     {<CLOCK_DRIVER_CELL> <OUTPUT_PIN>}
set ::MQ65_LOAD_PIN    <LOAD_CELL>/<INPUT_PIN>

# ---- site-specific RTL: replaces rtl_mem/mq65_icg.v (behavioural) in synthesis / LEC.
# Copy mq65_icg_site.example.v to mq65_icg_site.v and map it to the library ICG cell, or
# set this to "" to synthesise the behavioural model.
set ::MQ65_ICG_RTL [file dirname [info script]]/mq65_icg_site.v
