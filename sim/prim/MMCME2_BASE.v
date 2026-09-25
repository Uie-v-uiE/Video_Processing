`timescale 1ns/1ps
// MMCME2_BASE.v —— **只给仿真用**的 MMCM 行为模型（放在 sim/prim/，不在 src/rtl 里）
//
// 为什么需要它：本机 xsim 没有 UNISIM 行为库 —— 2026-09-25 实测
// `xelab` 报 `ERROR [VRFC 10-2063] Module <MMCME2_BASE> not found`。
// 后果不是"少一个模型"，是**任何例化 `clk_gen` 的顶层在仿真里根本起不来**，
// 而 `pl_video_top` 就是例化它的那一个 ⇒ 这就是 ISSUES #62 风险②
// （"顶层没有台架，缝差一拍看不见"）的物理原因之一：不是没人想写，是时钟起不来。
// 有了这一份，任务 #49（`tb_v98_top_seam`）才可能例化真顶层。
//
// 关键设计：**分频比一个都不写在这里**，全部从例化参数读回来。
//   ⇒ 不会有"RTL 改了比例、仿真模型还按老的跑"这种第二处说法（本项目一直在清那类账）。
//   真实出处：src/rtl/clocks/clk_gen.v（CLKIN1_PERIOD=20 ns、MULT_F=20 ⇒ VCO 1000 MHz、
//   CLKOUT0_DIVIDE_F=20 ⇒ 50 MHz 像素钟、CLKOUT1_DIVIDE=4 ⇒ 250 MHz、CLKOUT2_DIVIDE=5 ⇒ 200 MHz）。
//
// 这个模型**不能**用来验的两件事（说清楚，别假装能）：
//   ① 相位与占空比（PHASE 一律 0、DUTY 一律 50 %）⇒ CDC / 亚稳态 / 采样相位这类判据
//      仍然只能靠 RTL 里真实的 3 级链与 `snap_cross`，与本文件无关；
//   ② LOCKED 的真实判据（这里是"复位释放后 2 µs 拉起"）⇒ 任何"没锁定会怎样"的判据
//      要自己去驱动 `locked`，不许声称是本模型给的。
module MMCME2_BASE #(
    parameter BANDWIDTH          = "OPTIMIZED",
    parameter CLKFBOUT_MULT_F    = 5.000,
    parameter CLKFBOUT_PHASE     = 0.000,
    parameter CLKIN1_PERIOD      = 0.000,
    parameter CLKOUT0_DIVIDE_F   = 1.000,
    parameter CLKOUT0_DUTY_CYCLE = 0.500,
    parameter CLKOUT0_PHASE      = 0.000,
    parameter CLKOUT1_DIVIDE     = 1,
    parameter CLKOUT2_DIVIDE     = 1,
    parameter CLKOUT3_DIVIDE     = 1,
    parameter CLKOUT4_DIVIDE     = 1,
    parameter CLKOUT5_DIVIDE     = 1,
    parameter CLKOUT6_DIVIDE     = 1,
    parameter CLKOUT1_DUTY_CYCLE = 0.500,
    parameter CLKOUT2_DUTY_CYCLE = 0.500,
    parameter CLKOUT3_DUTY_CYCLE = 0.500,
    parameter CLKOUT4_DUTY_CYCLE = 0.500,
    parameter CLKOUT5_DUTY_CYCLE = 0.500,
    parameter CLKOUT6_DUTY_CYCLE = 0.500,
    parameter CLKOUT1_PHASE      = 0.000,
    parameter CLKOUT2_PHASE      = 0.000,
    parameter CLKOUT3_PHASE      = 0.000,
    parameter CLKOUT4_PHASE      = 0.000,
    parameter CLKOUT5_PHASE      = 0.000,
    parameter CLKOUT6_PHASE      = 0.000,
    parameter DIVCLK_DIVIDE      = 1,
    parameter REF_JITTER1        = 0.000,
    parameter STARTUP_WAIT       = "FALSE"
) (
    input  wire CLKIN1,
    input  wire CLKFBIN,                 // 真实例子里面是内部反馈，端口必须存在（漏它就是 `cannot find port`）
    input  wire PWRDWN,
    input  wire RST,
    output wire CLKOUT0, CLKOUT0B,
    output wire CLKOUT1, CLKOUT1B,
    output wire CLKOUT2, CLKOUT2B,
    output wire CLKOUT3, CLKOUT3B,
    output wire CLKOUT4, CLKOUT5, CLKOUT6,
    output wire CLKFBOUT, CLKFBOUTB,
    output wire LOCKED
);
    // 输出周期 = CLKIN1_PERIOD × DIVCLK_DIVIDE / CLKFBOUT_MULT_F × 本输出的分频值。
    // 返回 0 = 参数没给全（这时对应那一路**不动**，而不是动成一个假的 50 MHz ——
    // 假时钟比没时钟危险得多：它会喂出"看起来在跑"的波形）。
    function real per_of;
        input real div;
        begin
            if (CLKIN1_PERIOD <= 0.0 || CLKFBOUT_MULT_F <= 0.0 || DIVCLK_DIVIDE <= 0.0 || div <= 0.0)
                per_of = 0.0;
            else
                per_of = (CLKIN1_PERIOD * 1.0) * DIVCLK_DIVIDE / (CLKFBOUT_MULT_F * 1.0) * (div * 1.0);
        end
    endfunction

    // 半周期，量化到本 timescale 的 1 ps 网格（real 直接进 `#` 会被截成时间步长）。
    // ⚠ 先换算成"整 ps 的周期"再除以 2，**不要**在这里 +0.5 自己四舍五入：
    //   Verilog 的 real→integer 赋值本身就是"就近取整"，加了 0.5 等于取整两次，
    //   实测把 20 ns / 4 ns 各顶成 20.002 / 4.002 ns（100 ppm 的假时钟；
    //   第一版量出来 pix=49.995 MHz、5x=249.875 MHz 就是这个原因，改完是精确的 50/250/200）。
    function real h;
        input real p;
        integer q;
        begin
            q = p * 1000.0;                       // ps 网格，就近取整一次
            h = q / 2000.0;                       // 半周期（ns）
        end
    endfunction

    reg c0 = 1'b0, c1 = 1'b0, c2 = 1'b0, c3 = 1'b0, c4 = 1'b0, c5 = 1'b0, c6 = 1'b0;
    reg fb = 1'b0, lk = 1'b0;

    assign CLKOUT0  = c0;  assign CLKOUT0B  = ~c0;
    assign CLKOUT1  = c1;  assign CLKOUT1B  = ~c1;
    assign CLKOUT2  = c2;  assign CLKOUT2B  = ~c2;
    assign CLKOUT3  = c3;  assign CLKOUT3B  = ~c3;
    assign CLKOUT4  = c4;  assign CLKOUT5  = c5;  assign CLKOUT6  = c6;
    assign CLKFBOUT = fb;  assign CLKFBOUTB = ~fb;
    assign LOCKED   = lk;

    // 每一条都是"延迟翻转"的经典时钟模型；参数是 elaboration 常数，所以延迟也是常数。
    // ⚠ 用 `initial + if + forever` 而不是 `always if (...) #d x=~x;`：后者在条件为假时
    //   是一个**没有延迟的 always**，仿真会零延迟死循环卡住（写这一段时先踩了这个坑）。
    initial if (h(per_of(1.0))                > 0.0) forever #(h(per_of(1.0)))                fb = ~fb;
    initial if (h(per_of(CLKOUT0_DIVIDE_F))   > 0.0) forever #(h(per_of(CLKOUT0_DIVIDE_F)))   c0 = ~c0;
    initial if (h(per_of(CLKOUT1_DIVIDE))     > 0.0) forever #(h(per_of(CLKOUT1_DIVIDE)))     c1 = ~c1;
    initial if (h(per_of(CLKOUT2_DIVIDE))     > 0.0) forever #(h(per_of(CLKOUT2_DIVIDE)))     c2 = ~c2;
    initial if (h(per_of(CLKOUT3_DIVIDE))     > 0.0) forever #(h(per_of(CLKOUT3_DIVIDE)))     c3 = ~c3;
    initial if (h(per_of(CLKOUT4_DIVIDE))     > 0.0) forever #(h(per_of(CLKOUT4_DIVIDE)))     c4 = ~c4;
    initial if (h(per_of(CLKOUT5_DIVIDE))     > 0.0) forever #(h(per_of(CLKOUT5_DIVIDE)))     c5 = ~c5;
    initial if (h(per_of(CLKOUT6_DIVIDE))     > 0.0) forever #(h(per_of(CLKOUT6_DIVIDE)))     c6 = ~c6;

    initial begin
        lk = 1'b0;
        wait (RST === 1'b0 && PWRDWN === 1'b0);
        #2.0 lk = 1'b1;
        if (CLKIN1_PERIOD <= 0.0)
            $display("MMCME2_BASE(sim) ⚠ 例化没给 CLKIN1_PERIOD ⇒ 仿真时钟不会动（不是 bug，是这条判据要自己驱动）");
    end
endmodule
