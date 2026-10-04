# Quick synth smoke for pl_demo_top (catches RTL issues without full impl)
# 作用: 只建一个临时工程跑 pl_demo_top 的综合冒烟，不跑实现，用来在花 70 分钟之前抓 RTL 问题
# 前置条件: 仓库根下 src/rtl 的 util/clocks/video/process(含 rotate、zoom)/axi/hdmi/top 与 src/constraints/rk_zynq7020.xdc 在；vivado -mode batch 可用（工程 vivado/synth_smoke 每次 -force 重建）
# 产出物: vivado/synth_smoke.xpr 与 vivado/synth_smoke.runs/synth_1 的综合结果；stdout 的 SYNTH STATUS: 与 SYNTH OK / SYNTH FAIL（失败时把 runme.log 里的 ERROR/CRITICAL 行原样念出来）
# 关键参数: 无命令行参数、无 env 读取；top=pl_demo_top、器件 xc7z020clg484-2、launch_runs -jobs 4 都写死在本文件
# Usage: vivado -mode batch -source tcl/synth_pl_only.tcl
set root [file normalize [file join [file dirname [info script]] ..]]
set proj_dir [file join $root vivado]

create_project synth_smoke $proj_dir -part xc7z020clg484-2 -force
set rtl_files {}
foreach d {util clocks video process process/rotate process/zoom axi hdmi top} {
  foreach f [glob -nocomplain [file join $root src rtl $d *.v]] {
    lappend rtl_files $f
  }
}
add_files -norecurse $rtl_files
add_files -fileset constrs_1 -norecurse [file join $root src constraints rk_zynq7020.xdc]
set_property top pl_demo_top [current_fileset]
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs 4
wait_on_run synth_1
set status [get_property STATUS [get_runs synth_1]]
puts "SYNTH STATUS: $status"
if {[string match *Complete* $status] || [string match *Finished* $status]} {
  puts "SYNTH OK"
} else {
  puts "SYNTH FAIL"
  # print critical warnings/errors from log if available
  set log [file join $proj_dir synth_smoke.runs synth_1 runme.log]
  if {[file exists $log]} {
    set fp [open $log r]
    set data [read $fp]
    close $fp
    foreach line [split $data \n] {
      if {[string match *ERROR* $line] || [string match *CRITICAL* $line]} {
        puts $line
      }
    }
  }
}


