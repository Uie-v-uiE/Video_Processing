# build/tcl/probe_init_tied_rst.tcl —— 只读、一分钟：**把顶层那句 `rst_n = 1'b1` 一起综合**，看 INIT 还活不活
# 作用: 带着顶层那句常量复位（sys_rst_n(1'b1)）对 key_debounce 再做一次 OOC 综合，读四个寄存器的 INIT 是否还是 1'b1
# 前置条件: 仓库根下 src/rtl/util/key_debounce.v 在（只读它）；不依赖任何工程或 DCP；/tmp/kx/pu113/tied 可写（wrapper 落这里，不入库）
# 产出物: stdout 的 ROOT / FF <名> TYPE= INIT= / COMPARED=n bad=n / RESULT probe_init_tied PASS|FAIL 行（不写任何报告文件）
# 关键参数: 无命令行参数、无 env 读取；器件 xc7z020clg484-2、CNT_MAX=1000、被检单元名 u_t/key_*_reg 与地板 n=4 都写死在本文件
#   为什么还要这一步：`probe_init_after_synth.tcl` 里 `rst_n` 是 OOC 的自由输入 ⇒ 常量传播没发生，
#   而板上的真值就是 `system_top.v:250` 那句 `sys_rst_n(1'b1)` —— r112 网表里那颗 FDRE/INIT=0
#   正是"常量复位把复位支吃掉、连带把代码里的复位值也丢了"的结果。
#   所以只有"带着这句常量再综合一次"才回答"我声明的初值到底进没进位流"。
#   拷贝树：wrapper 写在 /tmp（不入库），RTL 从 src/rtl 读（只读）。
set root [file normalize [file join [file dirname [file dirname [info script]]]]]
set root [file normalize [file join $root ..]]
set wdir "/tmp/kx/pu113/tied"
file mkdir $wdir
set fh [open [file join $wdir tied_wrap.v] w]
puts $fh "`timescale 1ns/1ps"
puts $fh "// 只为了复现顶层那句常量：sys_rst_n 在 system_top.v:250 就是 1'b1"
puts $fh "module tied_wrap (input wire clk, input wire key_n,"
puts $fh "                    output wire pulse, output wire key_stable);"
puts $fh "    key_debounce #(.CNT_MAX(1000)) u_t (.clk(clk), .rst_n(1'b1), .key_n(key_n),"
puts $fh "                                      .pulse(pulse), .key_stable(key_stable));"
puts $fh "endmodule"
close $fh
puts "ROOT $root"
read_verilog [file join $root "src/rtl/util/key_debounce.v"]
read_verilog [file join $wdir "tied_wrap.v"]
if {[catch {synth_design -top tied_wrap -part xc7z020clg484-2 -mode out_of_context} e]} {
    puts "SYNTH-FAIL $e"; exit 1
}
set bad 0; set n 0
foreach name {u_t/key_stable_reg u_t/key_sync0_reg u_t/key_sync1_reg u_t/key_prev_reg} {
    set c [get_cells -quiet $name]
    if {[llength $c] == 0} { puts "NO_CELL $name"; incr bad; continue }
    puts "FF $name TYPE=[get_property REF_NAME $c] INIT=[get_property INIT $c]"
    if {[get_property INIT $c] ne "1'b1"} { puts "WRONG $name 上电值不是 1'b1"; incr bad }
    incr n
}
puts "COMPARED=$n bad=$bad (地板：n=0 就是探针空转)"
if {$bad == 0 && $n == 4} { puts "RESULT probe_init_tied PASS" } else { puts "RESULT probe_init_tied FAIL" }
exit 0
