`timescale 1ns/1ps
// 级 0 + 五级可重构效果链（spec §5.1 的"每级两种算法 + 每级可旁路"）：
//
//   级0 明暗   gamma_lut（256 项表，PS 通过第二个控制字的通道 2 逐项写；en=0 逐位旁路）
//   级1 颜色   proc_gray ─┬─ proc_invert
//   级2 滤波   proc_box_blur ─┬─ proc_sharpen      （同一级的两个选项，允许串起来）
//   级3 边缘   proc_sobel
//   级4 阈值   proc_binary（判决方向可选：亮于阈值 or 暗于阈值）
//   级5 形态学 proc_morph（腐蚀 / 膨胀）
//
// 与 V7 的差别写清楚，免得以后有人拿旧文档对不上：
//   * V7 的链是 gray → binary → blur → sobel → invert，二值化在滤波**之前**；
//     现在按 spec 的编号把阈值放到第 4 级，形态学接在它后面（形态学本来就是对面具图的操作）。
//   * 老的 5 个使能位仍然有效，但要先经 `effect_ctrl` 翻成下面这张表；
//     翻完之后 bit 的含义与 V7 完全一致（gray/binary/blur/sobel/invert）。
//
// stage_sel 位定义（**每一位一个算法**，只有级 5 那两位是互斥的）：
//   [0] 灰度        [1] 反色        [2] 3×3 模糊     [3] 3×3 锐化
//   [4] Sobel       [5] 二值化      [6] 二值化判决反相（只在 [5]=1 时有意义）
//   [7] 腐蚀        [8] 膨胀        —— [7] 与 [8] 同时为 1 时两个都不做：
//       开/闭运算是"先腐蚀再膨胀"，要**两遍** 3×3 窗口，本模块只有一遍，
//       与其悄悄实现成其中一种（屏上看着像"设了没反应"），不如明确旁路，
//       这个行为由 tb_v86 的 T14 钉住。
//
// 延迟：**固定 15 拍**，与任何一级开没开、同级选哪个算法都无关（每一级的 de 链都不受 bypass 影响，
// 同级两个算法是**串联**，所以两个都占自己的拍数）。逐拍账（tb_v86 实测就是它）：
//   灰度 1 + 反色 1 + 模糊 3 + 锐化 3 + Sobel 3 + 阈值 1 + 形态学 3 = 15
// 级 0 的 gamma **不在这一串里加拍**：分布式 RAM 是非同步读出，`de` 原样透传。
//   ⇒ 谁哪天把它改成寄存读出（BRAM 风格），LATENCY 必须同时改成 16 ——
//     改忘了不会静悄悄：tb_v86 的 T2 是**实测** de_in→de_out，与声明值不符就红。
// ⚠ 窗口级是**三拍**不是两拍：`de_in → de_d1 → de_d2 → de_out` 三级寄存器。
//   以前顶层把 V7 那条链写成 7 拍，而它真实是 1+1+3+3+1 = 9 ⇒ 左右窗一直错 2 个像素。
//   这件事与它的影响记在 ISSUES #54；顶层现在只能取 `u_pipe.LATENCY`，写不出第二个数。
// 顶层不许另写一个数：`pl_video_top` 用 `u_pipe.LATENCY` 取本模块的这一个值，
// 而 tb_v86 会**实测** de_in→de_out 再与它比 —— "数了几拍"由台架负责，模块里只有一份。
module proc_pipeline #(
    parameter H_ACTIVE = 512,
    parameter integer LATENCY = 15      // 声明的是本模块的固有延迟，**不许由外部覆盖**
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [8:0]  stage_sel,
    input  wire [7:0]  threshold,
    input  wire        gamma_en,        // 级 0：0 = 逐位旁路（tb_v88 的 T1 钉"关着就必须一动不动"）
    input  wire        gamma_wr,        // 翻转位：与 idx/data 同源同深度地过同步器（effect_ctrl）
    input  wire [7:0]  gamma_idx,
    input  wire [7:0]  gamma_data,
    input  wire        rotate_active,     // 状态用；窗口滤波本来就在目标域里做
    input  wire        hs_in,
    input  wire        vs_in,
    input  wire        de_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [15:0] din,
    output wire        de_out,
    output wire [15:0] dout
);
    wire w_gray  = stage_sel[0];
    wire w_inv   = stage_sel[1];
    wire w_blur  = stage_sel[2];
    wire w_sharp = stage_sel[3];
    wire w_sobel = stage_sel[4];
    wire w_bin   = stage_sel[5];
    wire bin_pol = stage_sel[6];
    wire w_erode = stage_sel[7] & ~stage_sel[8];
    wire w_dilate = stage_sel[8] & ~stage_sel[7];
    wire [1:0] morph_mode = w_erode ? 2'd1 : (w_dilate ? 2'd2 : 2'd0);

    wire        de1a; wire [15:0] d1a;
    wire        de1b; wire [15:0] d1b;
    wire        de2a; wire [15:0] d2a;
    wire        de2b; wire [15:0] d2b;
    wire        de3;  wire [15:0] d3;
    wire        de4;  wire [15:0] d4;

    // 级 0 明暗：gamma。**组合读出，不占拍数**，所以它不在上面那串逐拍账里。
    wire [15:0] d0;
    gamma_lut u_gamma (
        .clk(clk), .rst_n(rst_n),
        .en(gamma_en), .wr(gamma_wr), .idx(gamma_idx), .data(gamma_data),
        .din(din), .dout(d0)
    );

    // 级 1 颜色
    proc_gray u_gray (
        .clk(clk), .rst_n(rst_n), .bypass(~w_gray),
        .de_in(de_in), .din(d0), .de_out(de1a), .dout(d1a)
    );
    proc_invert u_inv (
        .clk(clk), .rst_n(rst_n), .bypass(~w_inv),
        .de_in(de1a), .din(d1a), .de_out(de1b), .dout(d1b)
    );

    // 级 2 滤波：两个选项串接，只开其中一个时另一个纯旁路
    proc_box_blur #(.H_ACTIVE(H_ACTIVE)) u_blur (
        .clk(clk), .rst_n(rst_n), .bypass(~w_blur),
        .hs_in(hs_in), .vs_in(vs_in), .de_in(de1b),
        .x_in(x_in), .y_in(y_in), .din(d1b),
        .de_out(de2a), .dout(d2a)
    );
    proc_sharpen #(.H_ACTIVE(H_ACTIVE)) u_sharp (
        .clk(clk), .rst_n(rst_n), .bypass(~w_sharp),
        .de_in(de2a), .x_in(x_in), .y_in(y_in), .din(d2a),
        .de_out(de2b), .dout(d2b)
    );

    // 级 3 边缘
    proc_sobel #(.H_ACTIVE(H_ACTIVE)) u_sobel (
        .clk(clk), .rst_n(rst_n), .bypass(~w_sobel),
        .vs_in(vs_in), .de_in(de2b),
        .x_in(x_in), .y_in(y_in), .din(d2b),
        .de_out(de3), .dout(d3)
    );

    // 级 4 阈值
    proc_binary u_bin (
        .clk(clk), .rst_n(rst_n), .bypass(~w_bin), .threshold(threshold), .pol(bin_pol),
        .de_in(de3), .din(d3), .de_out(de4), .dout(d4)
    );

    // 级 5 形态学
    proc_morph #(.H_ACTIVE(H_ACTIVE)) u_morph (
        .clk(clk), .rst_n(rst_n), .mode(morph_mode), .threshold(threshold),
        .de_in(de4), .x_in(x_in), .y_in(y_in), .din(d4),
        .de_out(de_out), .dout(dout)
    );
endmodule
