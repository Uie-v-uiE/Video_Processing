# build/tcl/uram_probe.tcl —— 一次性小实验：这颗 Zynq-7020 的工具**会不会/为什么不肯**把帧缓存形状放进 UltraRAM
#
#   vivado -mode batch -nojournal -source build/tcl/uram_probe.tcl
#
# 来龙去脉（`report/CONTEST_CHECKLIST.md` 第 3 项）：以前只试过在**真实帧缓存**上打
# `ram_style="ultramark"` / `"ultraram"`，两种拼法都被 2025.2.1 拒掉并静默退回 `auto`，
# 于是留下两笔糊涂账：①"9 块 UltraRAM 能换掉 48 块 BRAM"只是**算出来**的；
# ②那次失败里有多少是"工具不为这个形状选 UltraRAM"、多少是"我拿错了器件族的名字"
#   （`URAM1240` 是 UltraScale+ 的原语，7 系是 `URAM288`/`URAM288E`）——**不知道**。
#
# 这个探针把变量拆开：同一份 76800×32（= 512×300×16 bit，正是帧缓存的容量）的 RAM，
# 只改**端口形状**（1 写 1 读 vs 1 写 4 读 = 我们真实的双窗 × 4 字节读法），
# 各跑一遍综合，数它到底推断出几个 `URAM288`、几个 `RAMB36`/`RAMB18`。
# 判据不是"变好/变坏"，而是**一条从猜变成有的事实**：多读口是不是根本不允许进 UltraRAM。
set root [file normalize [file join [file dirname [info script]] .. ..]]
set dir [file join $root build uram_probe]
file mkdir $dir
set part xc7z020clg484-1

set f [open [file join $dir uram_probe.v] w]
puts $f {
// 1 写 1 读：UltraRAM 唯一能自然吃下的形状（简单双口）
(* ram_style = "ultramark" *) module ram_1w1r #(
    parameter DEPTH = 76800
)(
    input  wire        clk,
    input  wire        we,
    input  wire [16:0] waddr,
    input  wire [31:0] din,
    input  wire [16:0] raddr,
    output reg  [31:0] dout
);
    reg [31:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (we) mem[waddr] <= din;
        dout <= mem[raddr];
    end
endmodule

// 同样的属性，但**读口翻倍**（真实帧缓存要同时喂左/右窗与 4 个字节道）
(* ram_style = "ultramark" *) module ram_1w4r #(
    parameter DEPTH = 76800
)(
    input  wire        clk,
    input  wire        we,
    input  wire [16:0] waddr,
    input  wire [31:0] din,
    input  wire [16:0] r0, input  wire [16:0] r1, input  wire [16:0] r2, input  wire [16:0] r3,
    output reg  [31:0] d0, output reg  [31:0] d1, output reg  [31:0] d2, output reg  [31:0] d3
);
    reg [31:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (we) mem[waddr] <= din;
        d0 <= mem[r0]; d1 <= mem[r1]; d2 <= mem[r2]; d3 <= mem[r3];
    end
endmodule

// 对照组：完全不加属性，看工具自己怎么选
module ram_plain #(
    parameter DEPTH = 76800
)(
    input  wire        clk,
    input  wire        we,
    input  wire [16:0] waddr,
    input  wire [31:0] din,
    input  wire [16:0] raddr,
    output reg  [31:0] dout
);
    reg [31:0] mem [0:DEPTH-1];
    always @(posedge clk) begin
        if (we) mem[waddr] <= din;
        dout <= mem[raddr];
    end
endmodule
}
close $f

foreach top {ram_1w1r ram_1w4r ram_plain} {
    puts "########## URAM_PROBE $top ##########"
    if {[catch {
        create_project -force probe_$top [file join $root build uram_probe prj_$top] -part $part
        read_verilog [file join $dir uram_probe.v]
        synth_design -top $top -part $part
    } e]} {
        puts "PROBE $top SYNTH_FAILED $e"
        continue
    }
    set uram  [llength [get_cells -quiet -hier -filter {NAME =~ *URAM* || REF_NAME =~ URAM*}]]
    set ramb36 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB36E1}]]
    set ramb18 [llength [get_cells -quiet -hier -filter {REF_NAME == RAMB18E1}]]
    set lutram [llength [get_cells -quiet -hier -filter {REF_NAME =~ RAMD* || REF_NAME =~ RAMS*}]]
    set ff     [llength [get_cells -quiet -hier -filter {REF_NAME =~ FD*}]]
    puts "PROBE $top URAM=$uram RAMB36=$ramb36 RAMB18=$ramb18 LUTRAM_cells=$lutram FFs=$ff"
    # 工具自己怎么说（被忽略的属性会有 WARNING，抓出来贴日志）
    close_project
}
puts "URAM PROBE DONE（容量 76800x32 = 300 KB = 帧缓存大小）"
exit 0
