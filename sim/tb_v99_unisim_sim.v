`timescale 1ns/1ps
// tb_v99_unisim_sim —— 仿真用厂商原语占位件（sim/prim/）自己的判据
//
// 为什么这一条必须存在（2026-09-25）：`pl_video_top` 的树里有 MMCM / BUFG / OBUFDS / OSERDESE2，
// 而本机 xsim 没有 UNISIM 库（`xelab` 实测报 `Module <MMCME2_BASE> not found`）⇒
// **任何例化 `clk_gen` 的顶层在仿真里根本起不来**。这就是 ISSUES #62 风险②
// （"没有台架例化 pl_video_top ⇒ 缝差一拍看不见"）的物理原因之一：不是没人想写，是时钟起不来。
// 占位件让顶层台架（任务 #49）成为可能 —— 而"我自己写了个时钟模型，之后所有依赖时钟的判据
// 都拿它当真相"正是本项目最该防的自证，所以占位件先被这条判据量一遍。
//
// 判据（全部**固定时间窗 + 数边沿**，不靠"等某个事件"）：
//   C1 比例：5x 的边沿数必须正好是 pix 的 5 倍、200m 必须是 pix 的 4 倍。
//      为什么判比例而不是只判绝对值：绝对值这一条也判（C3），但**只有比例那条有牙** ——
//      谁把 `clk_gen.v` 的 `CLKOUT1_DIVIDE` 从 4 改成 5，模型会"正确地"跟着变 200 MHz，
//      而 TMDS 串行器要的 5× 就没了 ⇒ C1 红；若只判"pix 是 50 MHz"，同样的改动照样绿。
//   C2 复位/锁定：`locked` 必须在复位释放后为 1（顶层 `rst_pix_n = sys_rst_n & locked`，
//      它不起来说明整套复位树都是假的）。
//   C3 绝对周期：20 ns / 4 ns / 5 ns（= clk_gen 文件头声明的 50 / 250 / 200 MHz）。
//   C4 判据自己的反例：窗口太短（数不到 20 拍）时**必须报"量不出"而不是报绿** ——
//      这一条是防"空跑判据"（本项目记过好几次：条件从不成立 ⇒ 永远绿）。
//
// ⚠ 这个占位件**不锁相**：输出周期只由 `CLKIN1_PERIOD` 参数在 elaboration 时算一次，
//   仿真中途改输入时钟，输出**不会**跟着变（真 MMCM 会重新锁定）。所以本文件不许有
//   "换输入频率看输出跟不跟"这种判据 —— 那会红得不属于任何人的错。这条限制写在这里，
//   也写在 sim/prim/MMCME2_BASE.v 文件头（相位/占空比/抖动/真实 LOCKED 判据同样不建模）。
//
// ⚠ 为什么不用 `@(posedge …)` 等事件来量周期：第一版那么写，**台架挂死**（xsim 跑 4 分钟不出结果，
//   被我 kill 掉）。挂死的台架比红的台架糟得多 —— `run_sim.tcl` 是顺序跑的，一个卡住整轮回归没有结论。
//   现在这一版只有固定 `#` 延迟 + 计数器，并且带看门狗 `#500_000` 强制结束。
module tb_v99_unisim_sim;
    localparam integer WIN_NS = 1000;            // 计数窗口：对 50/250/200 MHz 恰好是 50/250/200 拍
    localparam real GATE_NS = 20.0;              // 一条 pix 周期的长度（写在这里只为了读日志，不参与判据）

    reg clk = 0;
    reg rst = 1;
    wire pix, pix5, m200, locked;
    integer e0 = 0, e1 = 0, e2 = 0;
    integer nfail = 0;

    always #10.0 clk = ~clk;                   // 50 MHz，与 clk_gen 的 CLKIN1_PERIOD=20.0 一致

    clk_gen u (
        .clk_in(clk), .rst_n(~rst),
        .clk_pix(pix), .clk_pix5x(pix5), .clk_200m(m200), .locked(locked)
    );

    always @(posedge pix) e0 = e0 + 1;
    always @(posedge pix5) e1 = e1 + 1;
    always @(posedge m200) e2 = e2 + 1;

    // ⚠ 两个宽度是按 **UTF-8 字节**算的，不是按字数：中文一字三字节，第一版给 tag 只留 30 字节，
    //   于是 "C1a 5x 正好是…" 被截成乱码打在日志里（判据本身是对的，但日志是给人当凭据读的）。
    task chk(input [8*60-1:0] tag, input cond, input [8*150-1:0] why);
        begin
            if (!cond) nfail = nfail + 1;
            $display("%s %0s | %0s", cond ? "PASS" : "FAIL", tag, why);
        end
    endtask

    initial begin
        // 看门狗：无论发生什么，500 µs 仿真时间后必须收尾（挂死 = 整轮回归没有结论）
        #500_000;
        $display("FAIL 看门狗到点 | 台架没自己结束 ⇒ 这一版又不该有等待事件的写法");
        $finish;
    end

    initial begin
        rst = 1'b1;
        #500;                              // 让复位真的压住一会儿
        rst = 1'b0;
        // 计数窗口从"复位释放"这一刻起算，并且**先把三个计数器清零**：
        // 不清零的话窗口里会混进复位前那 500 ns 的边沿，C3 的"周期 = 窗/边沿数"就会算错
        // （第一版正是这样，量出 13 ns 而不是 20 ns —— 数字看着像 bug，其实是我的尺子错位）。
        e0 = 0; e1 = 0; e2 = 0;
        #WIN_NS;
        $display("INFO 计数窗口 %0d ns（复位释放后起算）：pix=%0d 5x=%0d 200m=%0d locked=%b",
                 WIN_NS, e0, e1, e2, locked);
        // C4 先判"量到了没有"：没量到就不许判 C1/C3（防"空跑判据"）
        if (e0 < 20 || e1 < 60 || e2 < 40) begin
            $display("FAIL C4 窗口不够 | 三个计数器至少要 20/60/40 拍才算量得出比例（实到 %0d/%0d/%0d）",
                     e0, e1, e2);
            nfail = nfail + 1;
        end else begin
            $display("PASS C4 窗口够长 | 比例判据不是空跑（%0d/%0d/%0d 拍）", e0, e1, e2);
            // C1 比例：窗口是同一段时间，所以"边沿数之比 = 频率之比"
            chk("C1a 5x = 5 倍 pix", (e1 == 5 * e0) || (e1 == 5 * e0 + 5) || (e1 == 5 * e0 - 5),
                "TMDS 串行器要 5 倍时钟；边沿数允许 ±5 拍的相位边界");
            chk("C1b 200m = 4 倍 pix", (e2 == 4 * e0) || (e2 == 4 * e0 + 4) || (e2 == 4 * e0 - 4),
                "IDELAY 参考钟 200 MHz");
            // C3 绝对值：周期 = 窗口 / 边沿数（1000 ns 窗口对 50/250/200 MHz 正好是整数）
            chk("C3 三路的周期 = 20/4/5 ns",
                e0 > 0 && ((WIN_NS / e0) == 20) && ((WIN_NS / e1) == 4) && ((WIN_NS / e2) == 5),
                "clk_gen.v 文件头声明的 50/250/200 MHz");
        end
        chk("C2 locked 已拉起", locked === 1'b1, "`rst_pix_n = sys_rst_n & locked` 的另一半");

        if (nfail == 0) $display("RESULT tb_v99_unisim_sim PASS");
        else            $display("RESULT tb_v99_unisim_sim FAIL nfail=%0d", nfail);
        $finish;
    end
endmodule
