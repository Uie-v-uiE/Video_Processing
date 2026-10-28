# Build entry for the Vivado side. Run from the repository root:
#   vivado -mode batch -source scripts/build.tcl
#   vivado -mode batch -source scripts/build.tcl -tclargs bd_only
set here [file dirname [info script]]
source [file join $here tcl build_system_axigpio.tcl]
