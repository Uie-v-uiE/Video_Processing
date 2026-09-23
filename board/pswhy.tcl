connect
targets -set -filter {name =~ "*Cortex-A9 MPCore #0"}
stop
foreach r {pc lr sp cpsr} { if {[catch {rrd $r} v]} { puts "$r: FAIL $v" } else { puts "$r: $v" } }
# standalone 的默认 abort handler 什么都不打印（库里没开 DEBUG），只把出错指令地址写进这几个
# 全局再 while(1)。所以"板子没反应"时先读这里，而不是猜。地址来自 arm-none-eabi-nm。
puts "UndefinedExceptionAddr = [mrd -force 0x11488]"
puts "PrefetchAbortAddr      = [mrd -force 0x1148c]"
puts "DataAbortAddr          = [mrd -force 0x11490]"
con
puts "RESUMED"
exit
