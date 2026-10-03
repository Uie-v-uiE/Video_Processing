# build/tcl/probe_help_fanout2.tcl -- READ-ONLY help probe, no design opened (about 40 s, safe while a bench runs).
#   Why: before running the set_max_fanout A/B I must know (a) whether set_max_fanout exists at all in this
#     version, (b) what the tool itself says it is used for, and (c) which implementation step can actually act on
#     a fanout limit (phys_opt_design replication options / place_design directives). If no step honours the
#     constraint, an A/B on the same opt.dcp would produce a FAKE "no difference" -- the exact trap that a
#     single-variable experiment is supposed to avoid (repo rule: a positive control must be able to move).
#   Measured earlier the same way (build/evidence/r113_help_fanout_console.txt): report_design_analysis has NO
#     -fanout mode; report_high_fanout_nets is the real command.
#   Runtime labels stay ASCII (CJK in a Vivado puts label broke command substitution once).
puts "SMF_BEGIN"
catch {help set_max_fanout} e1
puts "HELP_RET_SET_MAX_FANOUT=$e1"
puts "SMP_BEGIN"
catch {help set_max_delay} e2
puts "HELP_RET_SET_MAX_DELAY=$e2"
puts "PHYSOPT_BEGIN"
catch {help phys_opt_design} e3
puts "HELP_RET_PHYS_OPT=$e3"
puts "PLACE_BEGIN"
catch {help place_design} e4
puts "HELP_RET_PLACE=$e4"
puts "HELP_DONE=1"
exit 0
