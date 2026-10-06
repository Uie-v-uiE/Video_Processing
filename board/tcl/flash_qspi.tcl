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
#   | `VP_QSPI_PART`  | Vivado 部件库里的配置存储器型号 | `mx25l25645g-qspi-x4-single` |
#   | `VP_HW_URL`     | hw_server 地址 | `localhost:3121` |
#   | `VP_FLASH_OFFSET` | 写入偏移（hex） | `0x0` |
#
# 这一支会**整片擦除**板载 QSPI：写之前脚本先做一次 blank check 并把结果打在日志里，
# 让"擦掉的是什么"留痕。运行时标签保持 ASCII（Vivado Tcl 按系统码页读 .tcl，CJK 的 puts
# 会吃掉字节并把控制台变成 grep 眼里的二进制）。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set img [file join $root "board/flash/BOOT.bin"]
if {[info exists ::env(VP_BOOT_IMAGE)]} { set img [file normalize $::env(VP_BOOT_IMAGE)] }
# 默认挑**实测量过那一支**：板子丝印是 W25Q256FV，可 Vivado 部件库里 `w25q256jw*` 的
# COMPATIBLE_PARTS 只列 zynquplus，拿去配 zynq7000 会在 program 那一步报 [Labtoolstcl 44-655]；
# 同为 32 MB / x4 的 macronix 档实测擦写与回读校验都过（board/measured/flash_qspi_2026-10-05.txt）。
set part {mx25l25645g-qspi-x4-single}
if {[info exists ::env(VP_QSPI_PART)]} { set part $::env(VP_QSPI_PART) }
set url {localhost:3121}
if {[info exists ::env(VP_HW_URL)]} { set url $::env(VP_HW_URL) }
set offs {0x0}
if {[info exists ::env(VP_FLASH_OFFSET)]} { set offs $::env(VP_FLASH_OFFSET) }

if {![file exists $img]} { puts "REFUSE: no boot image at $img"; exit 1 }
# ⚠ 喂法（2026-10-06 实测出来的，别再改回去）：Vivado 的 cfgmem 与 program_flash 的 `-fsbl`
#   都是"**给原料、工具自己打镜像**"的接口——PROGRAM.ZYNQ_FSBL 会把 FSBL 与启动头**包到 FILES 前面**。
#   把已经打好的 BOOT.bin 当 FILES 喂进去 = 镜像套镜像：flash 开头的分区表就成了垃圾。
#   证据（把 FSBL 从 JTAG 跑起来、让它自己念，board/measured/qspi_serial_live.txt）：
#     Boot mode is QSPI / FlashID=0xEF 0x40 0x19 WINBOND 256M Bits / QSPI is in 4-bit mode
#     Partition Count: 30064771079 (=0x700000007，垃圾) → INVALID_LOAD_ADDRESS_FAIL, FSBL Status=0xE0000000
#   而两次 program 的 "Verify Operation successful" 都比的是工具自己拼出来的东西 ⇒ 对可启动性零证明。
#   所以现在喂 bit + 应用 ELF，FSBL 单独给；BOOT.bin 只留作 bootgen 侧的凭据与尺寸参考。
set bitf [file join $root "build/system.bit"]
if {[info exists ::env(VP_BIT)]} { set bitf [file normalize $::env(VP_BIT)] }
set appf [file join $root "build/ps_app.elf"]
if {[info exists ::env(VP_APP)]} { set appf [file normalize $::env(VP_APP)] }
foreach f [list $bitf $appf] {
  if {![file exists $f]} { puts "REFUSE: 原料不在 $f"; exit 1 }
}
puts "FEED_BIT $bitf"
puts "FEED_APP $appf"
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
# 把兼容家族念出来，方便换板子时一眼看出挑错没有（这一步只念不判：真正拦它的是 program 那一步的 44-655）
if {[catch {get_property COMPATIBLE_PARTS $cm} compat]} { set compat "(读不到)" }
puts "CFGMEM_COMPAT $compat"
# 属性名按对象实际支持的列表来设：2025.2.1 的 hw_cfgmem 没有 PROGRAM.BBF_FILE 与
# PROGRAM.START_ADDRESS（写死会 17-142 中断），所以先 list_property 再逐个设，缺的只报 SKIP。
set props [list_property $cm]
puts "CFGMEM_PROPS $props"
set fsbl [file join $root "vitis/platform/zynq_fsbl/build/fsbl.elf"]
# PROGRAM.FILES 只收 .bit/.bin/.mcs（实测 44-518 "Valid file type extension .mcs or .bin"），
# 应用 ELF 不能直接进这一层——它已经在 bootgen 打好的 BOOT.bin 里了。
# 只有喂位流时才需要 ZYNQ_FSBL（那时工具负责打镜像）；喂 BOOT.bin 时**必须不给**，
# 否则就是镜像套镜像（本文件上面那段实测说明）。
if {![file exists $fsbl]} { puts "REFUSE: no FSBL at $fsbl"; close_hw_target; close_hw_server; exit 1 }
set feed_props [list \
    PROGRAM.FILES         [list $img] \
    PROGRAM.BLANK_CHECK   {0} \
    PROGRAM.ERASE         {1} \
    PROGRAM.CFG_PROGRAM   {1} \
    PROGRAM.VERIFY        {1} ]
switch -- [string tolower [file extension $img]] {
  ".bit" - ".mcs" {
    lappend feed_props PROGRAM.ZYNQ_FSBL $fsbl
    puts "FEED_MODE 原料（$img）⇒ 由工具打镜像，FSBL 单独给"
  }
  default {
    puts "FEED_MODE 原样写盘（$img 已是完整 BOOT.bin，含 FSBL+位流+应用）⇒ 不设 ZYNQ_FSBL"
  }
}
foreach {name val} $feed_props {
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
