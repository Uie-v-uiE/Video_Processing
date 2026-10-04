# 用途：READ-ONLY help probe, no design opened.
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：0=跑完
# build/tcl/probe_help_fanout3.tcl -- READ-ONLY help probe, no design opened.
#   Follow-up to probe_help_fanout2.tcl, which MEASURED two things that change the r114 plan:
#     * `set_max_fanout` does NOT exist in this Vivado: help says `ERROR: [Common 17-25] No topics matched`.
#       (So the A/B driver I had written would have died on a command name I invented from ISE-era memory.)
#     * `phys_opt_design` has the real levers: `-fanout_opt` (cell duplication on high-fanout critical nets),
#       `-force_replication_on_nets <args>` (force replication on named nets) and `-critical_cell_opt`.
#   This probe asks the remaining two questions before any experiment is run:
#     1) is MAX_FANOUT a documented settable property in this version (UG912 route)?
#     2) is `create_qor_suggestion` available (so the tool's own suggestion, not my guess, can drive a roll)?
#   Runtime labels stay ASCII.
puts "PROP_BEGIN"
catch {help set_property MAX_FANOUT} p1
puts "HELP_RET_PROP_MAX_FANOUT=$p1"
puts "CQS_BEGIN"
catch {help create_qor_suggestion} p2
puts "HELP_RET_CREATE_QOR_SUGGESTION=$p2"
puts "GPF_BEGIN"
catch {help get_properties} p3
puts "HELP_RET_GET_PROPERTIES=$p3"
puts "HELP_DONE=1"
exit 0
