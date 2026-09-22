`timescale 1ns/1ps
// bilin_lerp —— 双线性插值的**算术核**：4 个 RGB565 抽头 + Q8 小数位 → 1 个 RGB565。
//
// 与"抽头怎么取来"完全解耦（那部分是读口调度，见 OVERNIGHT_LOG §12），所以能单独
// 对着行为黄金模型逐位验。两级流水：横向一次、纵向一次。
//
// 三个精度决定，每个都有代价：
//   1. RGB565 → 8bit 通道用**位复制**展开（R8={r5,r5[2:0]}、G8={g6,g6[1:0]}），
//      不是左移补零。全 1 展开正好 255 ⇒ 纯白不会因展开变灰；补零的话 0x1F→0xF8。
//   2. 权重 Q8，fx/fy ∈ [0,255] 表示 [0,1) 的小数；两两权重之和恒为 256，
//      所以横向结果 ≤ 255×256 = 65280（17bit 封顶）、纵向 ≤ 255×65536 + 舍入
//      ⇒ 25bit，**不需要饱和**（这点在 TB 判据 2「四角同色 ⇒ 输出恒等」里被强制检验）。
//   3. 纵向合并后一次性 +2^15 再 >>16（四舍五入一次）。回包取高位截断。
module bilin_lerp (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] p00,   // (sx  , sy  )
    input  wire [15:0] p10,   // (sx+1, sy  )
    input  wire [15:0] p01,   // (sx  , sy+1)
    input  wire [15:0] p11,   // (sx+1, sy+1)
    input  wire [7:0]  fx,    // sx 的小数部分，Q8
    input  wire [7:0]  fy,    // sy 的小数部分，Q8
    output reg  [15:0] pix,
    output reg         vld
);
    function [7:0] rep5; input [4:0] v; begin rep5 = {v, v[2:0]}; end endfunction
    function [7:0] rep6; input [5:0] v; begin rep6 = {v, v[1:0]}; end endfunction

    wire [7:0] r00 = rep5(p00[15:11]), g00 = rep6(p00[10:5]), b00 = rep5(p00[4:0]);
    wire [7:0] r10 = rep5(p10[15:11]), g10 = rep6(p10[10:5]), b10 = rep5(p10[4:0]);
    wire [7:0] r01 = rep5(p01[15:11]), g01 = rep6(p01[10:5]), b01 = rep5(p01[4:0]);
    wire [7:0] r11 = rep5(p11[15:11]), g11 = rep6(p11[10:5]), b11 = rep5(p11[4:0]);

    // ---------------- 第一级：横向 ----------------
    wire [8:0] wx0 = 9'd256 - {1'b0, fx};
    wire [8:0] wx1 = {1'b0, fx};
    reg  [16:0] tr, tg, tb;            // 上边（源行 sy）   的横向插值
    reg  [16:0] br, bg, bb;            // 下边（源行 sy+1） 的横向插值
    reg  [7:0]  fy1;
    reg         v0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tr<=0; tg<=0; tb<=0; br<=0; bg<=0; bb<=0; fy1<=0; v0<=0;
        end else begin
            tr <= r00 * wx0 + r10 * wx1;
            tg <= g00 * wx0 + g10 * wx1;
            tb <= b00 * wx0 + b10 * wx1;
            br <= r01 * wx0 + r11 * wx1;
            bg <= g01 * wx0 + g11 * wx1;
            bb <= b01 * wx0 + b11 * wx1;
            fy1 <= fy;
            v0  <= 1'b1;
        end
    end

    // ---------------- 第二级：纵向 + 四舍五入 ----------------
    wire [8:0] wy0 = 9'd256 - {1'b0, fy1};
    wire [8:0] wy1 = {1'b0, fy1};
    wire [25:0] or_r = tr * wy0 + br * wy1 + 26'd32768;
    wire [25:0] or_g = tg * wy0 + bg * wy1 + 26'd32768;
    wire [25:0] or_b = tb * wy0 + bb * wy1 + 26'd32768;

    // >>16 之后必然 ≤255（权重和恒为 256），所以不夹取。
    // 注意不能写 or_r[24:16][7:3] —— Verilog-2001 不允许对位选结果再位选。
    wire [8:0] vr = or_r[24:16];
    wire [8:0] vg = or_g[24:16];
    wire [8:0] vb = or_b[24:16];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pix <= 16'd0; vld <= 1'b0;
        end else begin
            pix <= {vr[7:3], vg[7:2], vb[7:3]};
            vld <= v0;
        end
    end
endmodule
