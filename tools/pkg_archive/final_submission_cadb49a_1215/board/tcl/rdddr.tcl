# 作用：xsdb 只读回显——同时读 GPIO_0 那一个字与 DDR 起始处 8 个字，用来区分"控制字没写进去"和"数据没落内存"
# 前置条件：板子上电、位流已下载、hw_server 在跑、xsdb 能连到 APU
# 输入输出：无命令行参数；输出 stdout 的 GPIO 行与 8 行 DDR 字
# 退出码：脚本内无显式非 0 分支；connect/targets 取不到时由 xsdb 自己报错退出
connect
targets -set -filter {name =~ "*APU*"}
puts "GPIO = [mrd -force 0x41200000]"
puts "DDR  head:"
foreach l [mrd -force 0x10000000 8] { puts "  $l" }
exit
