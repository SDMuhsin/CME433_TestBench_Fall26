# Site config template for the mq65 flow. Copy to site/site.tcl (git-ignored) and replace
# every <PLACEHOLDER> with the values of your process kit. Sourced by syn/common/libs.tcl.
# Corners: ss = setup signoff (slow, hot), tt = typical / power, ff = hold (fast, cold).

set ::MQ65_KIT $::env(MQ65_KIT)

# ---- standard-cell timing libraries (.db)
set ::MQ65_LIBDIR <STDCELL_DB_DIR>
set ::MQ65_VLOG   <STDCELL_VERILOG_MODEL>
array set ::MQ65_CORNER_LIB {ss <STDCELL_LIB_SS> tt <STDCELL_LIB_TT> ff <STDCELL_LIB_FF>}
array set ::MQ65_CORNER_OC  {ss <OPCOND_SS> tt <OPCOND_TT> ff <OPCOND_FF>}
set ::MQ65_WLM_GROUP <WIRE_LOAD_SELECTION_GROUP>

# ---- physical (DC topographical mode)
set ::MQ65_MW     <MILKYWAY_DIR>
set ::MQ65_MW_REF <MILKYWAY_REFERENCE_LIB>
set ::MQ65_TF     <TECHFILE>
set ::MQ65_TLU    <RC_TECH_DIR>
set ::MQ65_TLU_MAP <RC_TECH_LAYER_MAP>
# RC setup for DC topographical mode: load the max / min RC model files of the given corners
# and the layer map with the DC command for your kit's RC model format.
proc mq65_rc_setup {max min} {
    <RC_SETUP_CMD> <MAX_OPT> [mq65_tlu $max] <MIN_OPT> [mq65_tlu $min] <MAP_OPT> $::MQ65_TLU_MAP
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

# ---- place and route, extraction, physical verification (phase 3)
set ::MQ65_BE      $::MQ65_KIT/<BACK_END_DIR>
set ::MQ65_LEF     $::MQ65_BE/<STD_CELL_LEF_FOR_THE_METAL_STACK>
set ::MQ65_GDS     $::MQ65_BE/<STD_CELL_GDS>
set ::MQ65_CDL     $::MQ65_BE/<STD_CELL_CDL_OR_SPICE>
set ::MQ65_ANT_RULES <ANTENNA_RULE_TCL_FILE>
# PVT of each corner library (the P&R tool picks the library view by PVT)
array set ::MQ65_CORNER_PVT {ss {<V> <T>} tt {<V> <T>} ff {<V> <T>}}
# min-RC model (hold corner)
set ::MQ65_TLU_MIN     <RC_TECH_FILE_BEST>
set ::MQ65_SITE        <CORE_SITE_NAME>
set ::MQ65_PG          {<POWER_NET> <GROUND_NET>}
set ::MQ65_FILLERS     {<FILLER_CELL_LARGEST> ... <FILLER_CELL_1>}
set ::MQ65_TIE         {<TIE_HIGH_CELL> <TIE_LOW_CELL>}
set ::MQ65_ANT_CELL    <ANTENNA_DIODE_CELL>
set ::MQ65_DONT_USE    {<DONT_USE_CELL_GLOBS>}
set ::MQ65_CTS_CELLS   {<CLOCK_BUFFER_GLOB> <CLOCK_INVERTER_GLOB>}
# routing layers (signal) and power-grid layers
set ::MQ65_LAYER_MIN   <LOWEST_SIGNAL_LAYER>
set ::MQ65_LAYER_MAX   <HIGHEST_SIGNAL_LAYER>
set ::MQ65_PG_LAYERS   {<RAIL_LAYER> <MESH_LAYER_V> <MESH_LAYER_H>}
# parasitic extraction: technology file and LEF/DEF -> technology layer maps
set ::MQ65_CCI         <EXTRACTION_KIT_DIR>
set ::MQ65_STAR_TECH   $::MQ65_CCI/<EXTRACTION_TECH_FILE_TYPICAL>
set ::MQ65_STAR_COND   {<LEF_LAYER> <TECH_LAYER> ...}
set ::MQ65_STAR_VIA    {<LEF_VIA> <TECH_VIA> ...}
# physical verification decks (main DRC of the same metal stack as the LEF, antenna, LVS)
set ::MQ65_DRC_DECK    <MAIN_DRC_DECK>
set ::MQ65_ANT_DECK    <ANTENNA_DRC_DECK>
set ::MQ65_LVS_DECK    <LVS_DECK>
# GDS stream-out: text layer per metal ({<metal_layer> <text_layer> ...}) and the datatype of
# layers that the kit's stream-out map does not write as datatype 0 ({<layer> <datatype> ...})
set ::MQ65_GDS_TEXT     {<METAL_LAYER> <TEXT_LAYER> ...}
set ::MQ65_GDS_DATATYPE {<LAYER> <DATATYPE> ...}
