# build/tcl/probe_help_fanout.tcl -- READ-ONLY shape measurement, no design opened.
#   Why: probe_timing_roster.tcl parses `report_design_analysis -fanout`, and the repo rule says a report's
#     shape must be measured, not guessed (the first roster run silently produced an EMPTY file because the
#     -limit/-interval options I guessed made the command fail -- D6 went red on my tool, not on the design).
#   MEASURED 2026-10-03 from this same Vivado 2025.2.1: `help report_design_analysis` has NO -fanout mode at
#     all (its modes are -complexity / -congestion / -timing / -routes / -logic_level_distribution /
#     -routed_vs_estimated / -qor_summary; the only fanout-ish option is -av_fanout_greater_than, a Rent
#     analysis threshold). So the design-wide high-fanout inventory has to come from report_high_fanout_nets,
#     and the per-path fanout columns belong to report_design_analysis -timing (HIGH FANOUT / CUMULATIVE
#     FANOUT). This probe prints those helps so the extraction is written against facts.
#   Runtime labels stay ASCII (Vivado Tcl reads this under the system codepage; CJK in a puts label broke
#   command substitution once and turned the console binary for grep).
puts "HELP_BEGIN"
catch {help report_design_analysis} herr
puts "HELP_ERR_RDA=$herr"
puts "HELP_HFN_BEGIN"
catch {help report_high_fanout_nets} hfnerr
puts "HELP_ERR_HFN=$hfnerr"
puts "HELP_QOR_BEGIN"
catch {help report_qor_suggestions} qerr
puts "HELP_ERR_QOR=$qerr"
puts "HELP_DONE=1"
exit 0
