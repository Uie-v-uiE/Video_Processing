# build/tcl/probe_init_after_synth.tcl —— 只读、单模块 OOC 综合：**声明初值到底有没有进 FF 的 INIT**
#   为什么必须单独问这一次：台架（xsim）认 `output reg key_stable = 1'b1`，不等于**综合**认。
#   而修法的整条理由就是"让位流带上上电值"——所以唯一算数的判据是综合后网表里那颗 FF 的 INIT。
#   这也是 #256 那条的机器判据（改前必须是红的：`build/evidence/r113_ff_init.txt` 量到 INIT=1'b0）。
# 用法：VP_VIVADO_BIN=<Vivado>/bin "$V/vivado" -mode batch -nojournal -source build/tcl/probe_init_after_synth.tcl
# 标签一律 ASCII（Vivado Tcl 的 CJK puts 会污染 grep 与命令替换）。
set root [file normalize [file join [file dirname [file dirname [info script]]]]]
set root [file normalize [file join $root ..]]
set part xc7z020clg484-2
puts "ROOT $root"
read_verilog [file join $root "src/rtl/util/key_debounce.v"]
if {[catch {synth_design -top key_debounce -part $part -mode out_of_context} e]} {
    puts "SYNTH-FAIL $e"
    exit 1
}
set n 0
foreach c [get_cells -quiet *] {
    set t [get_property REF_NAME $c]
    set i [get_property INIT $c]
    puts "FF $c TYPE=$t INIT=$i"
    incr n
}
puts "COMPARED=$n (地板：0 就是这次探针空转，不许当通过)"
# 期望（写死，别"看一眼觉得对"）：那颗 key_prev 若被优化掉会走 NO_CELL，由清单自己说话
set bad 0
foreach {name exp} {key_stable_reg 1'b1 key_sync0_reg 1'b1 key_sync1_reg 1'b1 key_prev_reg 1'b1} {
    set c [get_cells -quiet $name]
    if {[llength $c] == 0} { puts "NO_CELL $name（可能被优化掉，见上面清单）"; continue }
    set i [get_property INIT $c]
    if {$i eq $exp} { puts "OK   $name INIT=$i" } else { puts "WRONG $name INIT=$i 期望 $exp"; incr bad }
}
if {$bad == 0 && $n > 0} { puts "RESULT probe_init PASS" } else { puts "RESULT probe_init FAIL bad=$bad n=$n" }
exit 0
