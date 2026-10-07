# Purpose: read-only capture of the NAMED I/O timing gap list, to close IODEBT I7 honestly.
#   Why this file exists (2026-10-05, D2 of the D->C->B chain): `check_timing` in the archived
#     timing_summary gives two numbers in two different units for the same bucket --
#     the section header says "checking no_output_delay (12)" (pins) while the detail line says
#     "There are 6 ports with no output delay specified" (ports) -- and it never names them.
#     `build/check_io_timing_coverage.py` I7 requires ONE unit to reconcile all four buckets, so
#     with only counts we cannot tell which 6 ports Vivado means (e.g. does the tristate eth_mdio
#     count?). The named list comes from `check_timing -verbose` plus TIMING-18 details.
#   Rules already baked in (do not "improve" them back):
#     * Runtime labels are ASCII only. Vivado reads .tcl under the system codepage; a CJK puts
#       label once broke command substitution and turned the console into a binary file for grep.
#     * `expr` here forbids inline `info exists`; guards are separate steps.
#     * Open the dcp READ-ONLY (`open_checkpoint`), never launch a run, never write the project.
#   Usage:
#     VP_DCP=<path/to/system_top_routed.dcp> VP_LABEL=<id> \
#       "<Vivado>/bin/vivado.bat" -mode batch -nojournal -source build/tcl/probe_io_timing_names.tcl
#   Rows (machine-readable, one per line):
#     IONAMES|check=no_input_delay|pin=<name>            one per offending pin
#     IONAMES|check=no_output_delay|pin=<name>
#     IONAMES|count|no_input_delay=<n> no_output_delay=<n>
#     IONAMES|methodology|TIMING18|pin=<name>
#     IONAMES|DONE|rc=0        or:    IONAMES|REFUSE|<reason>
set root [file normalize [file join [file dirname [info script]] .. ..]]
set label "io_names"
if {[info exists ::env(VP_LABEL)]} { set label $::env(VP_LABEL) }
set dcp ""
if {[info exists ::env(VP_DCP)]} { set dcp [file normalize $::env(VP_DCP)] }
if {$dcp eq ""} {
  set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
}
if {![file exists $dcp]} { puts "IONAMES|REFUSE|no_dcp=$dcp"; exit 1 }

# NB: no open_project here on purpose. Opening the shared .xpr while an implementation is writing it
#   can corrupt the run, and a routed dcp opens on its own. Keep this probe project-free.
open_checkpoint $dcp

# --- 1. check_timing -verbose, then filter for the two delay buckets -----------
set ct [check_timing -verbose]
set nin 0
set nout 0
foreach line [split $ct \n] {
  set t [string trim $line]
  if {[string match "*no input delay specified*" $t]} {
    # the verbose body names ports/pins after the description; grab every token that looks like a port
    foreach tok [regexp -all -inline -- {\w+(?:\[\d+\])?} $t] {
      set p [get_ports -quiet $tok]
      if {[llength $p] > 0} {
        puts "IONAMES|check=no_input_delay|pin=$tok"
        incr nin
        break
      }
    }
  }
  if {[string match "*no output delay specified*" $t]} {
    foreach tok [regexp -all -inline -- {\w+(?:\[\d+\])?} $t] {
      set p [get_ports -quiet $tok]
      if {[llength $p] > 0} {
        puts "IONAMES|check=no_output_delay|pin=$tok"
        incr nout
        break
      }
    }
  }
}
puts "IONAMES|count|no_input_delay=$nin no_output_delay=$nout"

# --- 2. TIMING-18 details name pins on their own; capture them as a second view --
set m [report_methodology -checks {TIMING-18} -return_string]
foreach line [split $m \n] {
  foreach tok [regexp -all -inline -- {\w+(?:\[\d+\])?} $line] {
    set p [get_ports -quiet $tok]
    if {[llength $p] > 0} { puts "IONAMES|methodology|TIMING18|pin=$tok" }
  }
}
close_project
puts "IONAMES|DONE|rc=0|label=$label"
