`timescale 1ns/1ps
// 功能：被测模块 `clk_gen`（例化名 u，即 sim/prim/ 下的厂商原语占位件）；覆盖点：三路输出时钟的
//        频率比例、绝对周期与 locked 起没起来，钉住"用它搭的顶层台架时钟可信"这一前提。
// 激励与检查：输入 clk 由 `always #10.0` 翻转（20 ns 周期 = 50 MHz，与 CLKIN1_PERIOD=20.0 一致），
//        rst 上电为 1、压 500 ns 后释放；释放瞬间把三个计数器 e0/e1/e2 清零（不清会把复位前那 500 ns
//        的边沿混进窗里、把周期量成 13 ns），再用固定窗 WIN_NS=1000 ns 数上升沿，全程不等事件；
//        判定条件：C4 先要 e0>=20 && e1>=60 && e2>=40（不够就只报"量不出"、不许判 C1/C3），
//        C1a 要 e1==5*e0（容 ±5 拍）、C1b 要 e2==4*e0（容 ±4 拍）、C3 要 WIN_NS/e0==20 且
//        WIN_NS/e1==4 且 WIN_NS/e2==5、C2 要 locked===1'b1。
// 预期结果：通过时每判据打一行 `PASS <C1a/C1b/C3/C2 标签> | <说明>`、窗口够长时另打
//        `PASS C4 窗口够长 | 比例判据不是空跑（<e0>/<e1>/<e2> 拍）`，末行 `RESULT tb_v99_unisim_sim PASS`；
//        失败时对应那条打 `FAIL <标签> | …` 并 nfail 加一，末行改打
//        `RESULT tb_v99_unisim_sim FAIL nfail=<n>`；窗口不够时打 `FAIL C4 窗口不够 | … （实到 <e0>/<e1>/<e2>）`
//        并跳过 C1/C3；看门狗 #500_000 到点打含 `FAIL 看门狗到点` 的那一行。
// tb_v99_unisim_sim —— 仿真用厂商原语占位件（sim/prim/）自己的判据。跑法：bash sim/run_one.sh tb_v99_unisim_sim
// 钉住的缺陷：本机 xsim 无 UNISIM 库（xelab 报 `Module <MMCME2_BASE> not found`）⇒ 任何例化 clk_gen 的顶层在仿真里起不来
// —— ISSUES #62 风险②（"没有台架例化 pl_video_top ⇒ 缝差一拍看不见"）的物理原因。自己写的时钟模型不能当真相 ⇒ 先量一遍。
// 判据（全部**固定时间窗 + 数边沿**，不靠"等某个事件"）：
//   C1 比例：5x 边沿数 = pix 的 5 倍、200m = pix 的 4 倍 | C2 locked 复位释放后为 1 | C3 绝对周期 20/4/5 ns
//   C4 判据自己的反例：窗口太短（数不到 20 拍）必须报"量不出"而不是报绿 —— 防"空跑判据"
module tb_v99_unisim_sim;
    localparam integer WIN_NS = 1000;            // 计数窗口：对 50/250/200 MHz 恰好是 50/250/200 拍
    localparam real GATE_NS = 20.0;              // 一条 pix 周期的长度（写在这里只为了读日志，不参与判据）

    reg clk = 0;
    reg rst = 1;
    wire pix, pix5, m200, locked;
    integer e0 = 0, e1 = 0, e2 = 0;
    integer nfail = 0;

    always #10.0 clk = ~clk;                   // 50 MHz，与 clk_gen 的 CLKIN1_PERIOD=20.0 一致

    // ⚠ 占位件**不锁相**：输出周期只在 elaboration 时按 CLKIN1_PERIOD 算一次，仿真中途改输入时钟输出不会跟
    //   （真 MMCM 会重新锁定）⇒ 本文件不许有"换输入频率看输出跟不跟"的判据。详见 sim/prim/MMCME2_BASE.v 文件头。
    clk_gen u (
        .clk_in(clk), .rst_n(~rst),
        .clk_pix(pix), .clk_pix5x(pix5), .clk_200m(m200), .locked(locked)
    );

    always @(posedge pix) e0 = e0 + 1;
    always @(posedge pix5) e1 = e1 + 1;
    always @(posedge m200) e2 = e2 + 1;

    // ⚠ tag/why 宽度按 **UTF-8 字节**算（中文一字三字节）：只留 30 字节会把判据名截成乱码
    //   —— 判据本身没错，但日志是给人当凭据读的，所以这里给到 60/150 字节。
    task chk(input [8*60-1:0] tag, input cond, input [8*150-1:0] why);
        begin
            if (!cond) nfail = nfail + 1;
            $display("%s %0s | %0s", cond ? "PASS" : "FAIL", tag, why);
        end
    endtask

    initial begin
        // 看门狗：500 µs 仿真时间后必须收尾。挂死的台架比红的更糟（run_sim.tcl 顺序跑，一个卡住整轮没结论）
        // ⇒ 这里只用固定 # 延迟 + 计数器，不写 @(posedge …) 这类等事件的量法。
        #500_000;
        $display("[tb_v99_unisim_sim.v:63] FAIL 看门狗到点 | 台架没自己结束 ⇒ 这一版又不该有等待事件的写法");
        $finish;
    end

    initial begin
        rst = 1'b1;
        #500;                              // 让复位真的压住一会儿
        rst = 1'b0;
        // 计数窗口从"复位释放"起算，并且**先清零**：不清就混进复位前那 500 ns 的边沿，
        // C3 的"周期 = 窗/边沿数"会量出 13 ns —— 尺子错位，不是 DUT 的 bug。
        e0 = 0; e1 = 0; e2 = 0;
        #WIN_NS;
        $display("[tb_v99_unisim_sim.v:76] INFO 计数窗口 %0d ns（复位释放后起算）：pix=%0d 5x=%0d 200m=%0d locked=%b",
                 WIN_NS, e0, e1, e2, locked);
        // C4 先判"量到了没有"：没量到就不许判 C1/C3（防"空跑判据"）
        if (e0 < 20 || e1 < 60 || e2 < 40) begin
            $display("[tb_v99_unisim_sim.v:80] FAIL C4 窗口不够 | 三个计数器至少要 20/60/40 拍才算量得出比例（实到 %0d/%0d/%0d）",
                     e0, e1, e2);
            nfail = nfail + 1;
        end else begin
            $display("[tb_v99_unisim_sim.v:84] PASS C4 窗口够长 | 比例判据不是空跑（%0d/%0d/%0d 拍）", e0, e1, e2);
            // C1 比例：同一段时间窗 ⇒ 边沿数之比 = 频率之比。**只有这条有牙** —— 谁把 CLKOUT1_DIVIDE 从 4
            // 改成 5，模型会"正确地"跟着变 200 MHz，TMDS 要的 5× 就没了 ⇒ C1 红；只判"pix = 50 MHz"则照样绿。
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
