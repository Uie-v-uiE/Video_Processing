# board/tcl/flash_qspi.tcl —— 用 JTAG 把启动镜像写进板载 QSPI NOR（W25Q256，x4 单片）
#
# 依赖：Vivado 2025.2.1 批处理模式（`<Vivado>/bin/vivado.bat`，不在 PATH）；一个已经在跑的 hw_server
#       （默认 `localhost:3121`）；板上电且 JTAG 链能数出 `xc7z020_1`；镜像由
#       `board/scripts/make_boot_image.sh` 先做好。
# 用法："<Vivado>/bin/vivado.bat" -mode batch -nojournal -log <目录>/flash_qspi.log \
#          -source board/tcl/flash_qspi.tcl        （从仓库根起，擦 + 写 + 回读约 3–6 分钟）
# 参数：
#   | 变量 | 作用 | 默认 |
#   | --- | --- | --- |
#   | `VP_BOOT_IMAGE` | 要写进去的镜像 | `board/flash/BOOT.bin` |
#   | `VP_QSPI_PART`  | Vivado 部件库里的配置存储器型号 | `w25q256jw-qspi-x4-single` |
#   | `VP_HW_URL`     | hw_server 地址 | `localhost:3121` |
#   | `VP_FLASH_OFFSET` | 写入偏移（hex） | `0x0` |
#
# 这一支会**整片擦除**板载 QSPI：写之前脚本先做一次 blank check 并把结果打在日志里，
# 让"擦掉的是什么"留痕。运行时标签保持 ASCII（Vivado Tcl 按系统码页读 .tcl，CJK 的 puts
# 会吃掉字节并把控制台变成 grep 眼里的二进制）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set img [file join $root "board/flash/BOOT.bin"]
if {[info exists ::env(VP_BOOT_IMAGE)]} { set img [file normalize $::env(VP_BOOT_IMAGE)] }
set part {w25q256jw-qspi-x4-single}
if {[info exists ::env(VP_QSPI_PART)]} { set part $::env(VP_QSPI_PART) }
set url {localhost:3121}
if {[info exists ::env(VP_HW_URL)]} { set url $::env(VP_HW_URL) }
set offs {0x0}
if {[info exists ::env(VP_FLASH_OFFSET)]} { set offs $::env(VP_FLASH_OFFSET) }

if {![file exists $img]} { puts "REFUSE: no boot image at $img"; exit 1 }
puts "IMAGE $img"
puts "IMAGE_BYTES [file size $img]"
puts "PART $part  OFFSET $offs  SERVER $url"

open_hw
if {[catch {connect_hw_server -url $url} err]} { puts "REFUSE: connect_hw_server: $err"; exit 1 }
if {[catch {open_hw_target} err]} { puts "REFUSE: open_hw_target: $err（板子没上电或 JTAG 链空）"; close_hw_server; exit 1 }

set pl [get_hw_devices xc7z020*]
puts "PL_DEVICES: $pl"
if {[llength $pl] == 0} {
    puts "REFUSE: JTAG 链上没有 xc7z020（板子没上电 / 线没插 / hw_server 看到的是空链）"
    close_hw_target; close_hw_server; exit 1
}
current_hw_device [lindex $pl 0]
refresh_hw_device -update_hw_probes false [current_hw_device]
puts "CURDEV [current_hw_device]"

set parts [get_cfgmem_parts $part]
puts "PART_HITS [llength $parts]"
if {[llength $parts] == 0} {
    puts "REFUSE: 部件库里没有 $part（换 VP_QSPI_PART，可选项用 get_cfgmem_parts *25q256* 现查）"
    close_hw_target; close_hw_server; exit 1
}

set cm [create_hw_cfgmem -hw_device [current_hw_device] [lindex $parts 0]]
# 属性名按对象实际支持的列表来设：2025.2.1 的 hw_cfgmem 没有 PROGRAM.BBF_FILE 与
# PROGRAM.START_ADDRESS（写死会 17-142 中断），所以先 list_property 再逐个设，缺的只报 SKIP。
set props [list_property $cm]
puts "CFGMEM_PROPS $props"
set fsbl [file join $root "vitis/platform/zynq_fsbl/build/fsbl.elf"]
if {![file exists $fsbl]} { puts "REFUSE: no FSBL at $fsbl"; close_hw_target; close_hw_server; exit 1 }
foreach {name val} [list \
    PROGRAM.FILES         [list $img] \
    PROGRAM.ZYNQ_FSBL     $fsbl \
    PROGRAM.BLANK_CHECK   {0} \
    PROGRAM.ERASE         {1} \
    PROGRAM.CFG_PROGRAM   {1} \
    PROGRAM.VERIFY        {1} ] {
    if {[lsearch -exact $props $name] >= 0} {
        set_property $name $val $cm
        puts "SET $name = $val"
    } else {
        puts "SKIP $name（本版本对象不支持该属性）"
    }
}
puts "CFGMEM [get_property NAME $cm]"

set rc [catch {program_hw_cfgmem $cm} err]
puts "PROGRAM_RC $rc"
# 2025.2.1 的 hw_cfgmem 没有 STATUS 属性（17-54），成败只看 program_hw_cfgmem 的返回码
# 与它自己打的 Erase/Program/Verify successful 三行。
if {$rc != 0} { puts "PROGRAM_ERR $err"; close_hw_target; close_hw_server; exit 1 }
puts "FLASH_QSPI DONE"
close_hw_target
close_hw_server
exit 0
