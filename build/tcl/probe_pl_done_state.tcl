# 作用: 只读地问 JTAG 一句"PL 现在配好了吗"，用来在上电后区分"位流已从 flash 起来"与"链上没人配置"
# 前置条件: hw_server 在 localhost:3121；跑法 `vivado -mode batch -nojournal -source 本文件`
# 产出物: stdout 的 RP_BEGIN/RP_END 之间那份 xc7z020 全属性清单（含 STATUS），不落任何文件
# 关键参数: 无命令行参数、无 env 读取；器件名 xc7z020_1 写死在本文件
# 退出码: 0=跑完（连不上由 Vivado 报错退出非 0）
# 为什么要它：擦写 QSPI 前必须知道拨码在哪一档，而 program_flash 的拒绝只在控制台出现过、没留凭据。
#   flash 里那份镜像会配置 PL ⇒ 冷上电后 STATUS 是"已配置"这一族；拨在 JTAG 档则没人配置它。
#   这条判据只 report_property，不发复位、不写任何东西，所以对在跑的系统是零副作用。
# 运行期字符串保持 ASCII（GBK 控制台会把 CJK 标签打成乱码，见同类教训）。
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
set dev [get_hw_devices xc7z020_1]
if {$dev eq ""} {
  puts "DEV_NOT_FOUND"
  exit 1
}
set rc [catch {report_property $dev} rp err]
puts "RP_RC=$rc"
puts "RP_BEGIN"
puts $rp
puts "RP_END"
close_hw_target
disconnect_hw_server
close_hw_manager
exit 0
