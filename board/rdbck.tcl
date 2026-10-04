# 作用：xsdb 只读回显——把 GPIO_0 基地址那一个字读回来，确认上位机写的 lane 号有没有落到板上
# 前置条件：板子上电、位流已下载、hw_server 在跑、xsdb 能连到 APU
# 输入输出：无命令行参数；输出 stdout 一行 GPIO@0x41200000 = <mrd 回读值>
# 退出码：脚本内无显式非 0 分支；connect/targets 取不到时由 xsdb 自己报错退出
connect
targets -set -filter {name =~ "*APU*"}
puts "GPIO@0x41200000 = [mrd -force 0x41200000]"
exit
