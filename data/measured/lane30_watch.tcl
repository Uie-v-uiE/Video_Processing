# 用途：scan $gv {%x} gi
# 输入：无字面量输入路径；参数解析见本文件
# 输出：stdout
# 退出码：脚本内无显式 exit ⇒ 随最后一条命令（正常跑完为 0）
catch {connect -host localhost -port 3121} ce
puts "CONNECT=$ce"
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
puts "RAW=[mrd -force 0x41200000]"
for {set i 0} {$i < 300} {incr i} {
  set gv ""
  regexp {:\s*([0-9a-fA-F]{1,8})} [mrd -force 0x41200000] -> gv
  if {$gv eq ""} { puts "BADG $i"; after 150; continue }
  scan $gv {%x} gi
  set keep [expr {$gi & 0x07FFFFFF}]
  catch {mwr -force 0x41200000 [format 0x%08x [expr {$keep | (30 << 27)}]]}
  set sv ""
  regexp {:\s*([0-9a-fA-F]{1,8})} [mrd -force 0x41210000] -> sv
  if {$sv eq ""} { puts "BADS $i"; after 150; continue }
  set v2 ""
  regexp {:\s*([0-9a-fA-F]{1,8})} [mrd -force 0x41200000] -> v2
  puts "S $i $sv $gv $v2"
  after 150
}
puts WATCH_DONE