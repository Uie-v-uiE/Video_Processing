# build/tcl/probe_ff_init.tcl —— 只读：那几个寄存器的**位流上电值**到底是什么（不猜）
#   为什么必须量而不能推：拷贝树台架第一次跑就 BLOCKED —— 仿真里没复位的 reg 读到 X，
#   而硬件里 FDRE 上电是位流的 INIT（多半是 0）。这两件事不一样，谁替谁说话都不算凭据。
#   要判的命题只有一条：`system_top.v:250` 把 `sys_rst_n` 恒接 1'b1 ⇒ `if (!rst_n) key_stable <= 1'b1;`
#   是死支 ⇒ 综合把复位摘掉之后，`key_stable` 的上电值是 **0（=按下）** 还是 **1（=松手）**？
#   前一种 ⇒ 上电 20 ms 后必然出现一次"松手沿" ⇒ key_long 补发短按 ⇒ angle 白涨 1°；后一种 ⇒ 这条解释作废。
# 用法：vivado -mode batch -nojournal -source build/tcl/probe_ff_init.tcl
# 标签全 ASCII；两份 dcp 都问（综合后 / 布线后），不一致也要看得见。
set root [file normalize [file join [file dirname [info script]] .. ..]]
foreach stage {synth impl} {
    if {$stage eq "synth"} {
        set dcp [file join $root "vivado_system/zynq_video_sys.runs/synth_1/system_top.dcp"]
    } else {
        set dcp [file join $root "vivado_system/zynq_video_sys.runs/impl_1/system_top_routed.dcp"]
    }
    if {![file exists $dcp]} { puts "SKIP $stage no dcp"; continue }
    puts "===== STAGE $stage  DCP $dcp ====="
    if {[catch {open_checkpoint $dcp} e]} { puts "REFUSE $stage open failed: $e"; continue }
    set pats [list u_pl/u_k1/key_stable_reg u_pl/u_k1/key_sync1_reg u_pl/u_k1/key_sync0_reg \
                  u_pl/u_k1/key_prev_reg u_pl/u_k1/armed_reg u_pl/u_k1/acnt_reg* \
                  u_pl/u_k1/cnt_reg* u_pl/u_k1l/fired_reg u_pl/u_k1l/cnt_reg* \
                  u_pl/u_ang/angle_reg* u_pl/u_ang/fs_s_reg* u_pl/u_k2/key_stable_reg]
    set n 0
    foreach p $pats {
        set cells [get_cells -quiet $p]
        if {[llength $cells] == 0} { puts "NO_CELL $p（这一轮没这个名字？例如 r110 没有 armed/acnt）"; continue }
        foreach c $cells {
            set t [get_property REF_NAME $c]
            set i [get_property INIT $c]
            # IS_RESET_USED 这类属性名不确定存在 ⇒ catch，别让整个探针因为一个属性死掉
            if {[catch {get_property IS_RESET_USED $c} r]} { set r "?" }
            puts "FF $c TYPE=$t INIT=$i RST_USED=$r"
            incr n
        }
    }
    puts "COMPARED=$n  (地板：一条都没数到就是这次实验空转)"
    # 还有一问：这一域真的没有任何复位吗？把 u_k1 里带 CLR/RST 的引脚数出来
    set withclr [get_cells -quiet -filter {REF_NAME =~ "FD*" && IS_SEQUENTIAL && NAME =~ "u_pl/u_k1/*"}]
    set cnt_clr 0
    foreach c $withclr {
        if {[llength [get_pins -quiet $c/*CLR]] > 0 || [llength [get_pins -quiet $c/*PRE]] > 0} { incr cnt_clr }
    }
    puts "U_K1_FDS=[llength $withclr]  带 CLR/PRE 引脚的=$cnt_clr"
    close_design
}
exit 0
