# Layout PNG of a finished run (OpenROAD save_image, headless, macro instance names shown):
#   QT_QPA_PLATFORM=offscreen openroad -no_init -exit src/flow/report/render.tcl   (from anywhere)
# env: RUN_DIR (default src/flow/runs/mb_final), PNG (default src/docs/mb_chip_layout.png)
# (LibreLane's own KLayout render, fill included, is runs/<tag>/final/render/mb_chip.png.)
set flow [file dirname [file dirname [file normalize [info script]]]]
set run [expr {[info exists ::env(RUN_DIR)] ? $::env(RUN_DIR) : "$flow/runs/mb_final"}]
set png [expr {[info exists ::env(PNG)] ? $::env(PNG) : "$flow/../docs/mb_chip_layout.png"}]
read_db $run/final/odb/mb_chip.odb
save_image -area {0 0 1675 1110} -width 2400 $png
puts "RENDER_DONE $png"
