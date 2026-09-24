`timescale 1ns/1ps
// key_long —— "按住不放"检测器（与 `key_debounce` 配套，把同一个按键用出两种语义）。
//
// 为什么要它：板上只有两个按键，而且已经被"旋转 ±1°"占了（R12/R13 板级验过）。
// 现在要加"切换片源"，没有第三个键 —— 于是短按保持原意，长按多出一个事件。
// 输出是**翻转位 tog 而不是脉冲**：本模块跑在 sys_clk，消费者在 clk_pix / axi_clk，
// 脉冲跨域会被吃掉（这正是主线 `ps_publish` 与 ISSUES #36 那笔账的教训），
// 翻转位过 3 级同步后在目的域异拍还原成脉冲，才是安全的。
//
// 一次按下只发一次：`fired` 保证长按事件不重复，松开后才重新武装。
//
// 2026-09-24（ISSUES #55，用户报"长按总先触发一次短按 / 长按有时没反应"）改三处：
//   1. `short_pulse`：**松手时**才发，且只有"没到过长按阈值"的那次按下才算短按。
//      以前短按由 `key_debounce` 在**按下沿**发 ⇒ 每次长按必然先转 1°。
//      旋转的语义没变（一次短按 = +1°），变的只是发的时刻。
//      KEY2 仍然吃按下沿的脉冲 —— 它的语义是"连续反向转"，越早发越好用。
//   2. 阈值 1.2 s → **0.6 s**：1.2 s 靠手掐太不稳定，是"按了没反应"的另一半成因。
//   3. `holding`：按住超过 0.2 s 就置 1，给 LED 当"正在计时"的反馈（没反馈时用户只能重按，
//      而重按在旧模式环里会多走一格 ⇒ 走到"锁图卡"，就是"看着像自己变成彗星图"那条）。
module key_long #(
    parameter integer HOLD_CYC = 30_000_000,      // sys_clk 50 MHz ⇒ 0.6 s
    parameter integer ARM_CYC  = 10_000_000       // ⇒ 0.2 s：这之后 LED 亮，告诉操作者"还在计"
)(
    input  wire clk,
    input  wire rst_n,
    input  wire pressed,        // 1 = 已按下（即 key_debounce 的 ~key_stable，已去抖）
    output reg  tog,            // 每满足一次长按翻转一次
    output reg  short_pulse,    // 松手时发：这次没到长按阈值 ⇒ 算一次短按
    output reg  holding         // 按住且已过 ARM_CYC、还没到阈值
);
    localparam [27:0] HOLD = HOLD_CYC[27:0];
    localparam [27:0] ARM  = ARM_CYC[27:0];
    reg [27:0] cnt;
    reg        fired;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 28'd0; fired <= 1'b0; tog <= 1'b0;
            short_pulse <= 1'b0; holding <= 1'b0;
        end else begin
            short_pulse <= 1'b0;                       // 脉冲默认只活一拍
            if (!pressed) begin
                // 松手：到过阈值就什么都不补发；没到过 = 一次短按（cnt != 0 排除"从没按下过"）
                if (!fired && cnt != 28'd0) short_pulse <= 1'b1;
                cnt <= 28'd0; fired <= 1'b0; holding <= 1'b0;
            end else begin
                holding <= (cnt >= ARM) && !fired;
                if (!fired) begin
                    if (cnt >= HOLD - 28'd1) begin
                        cnt <= 28'd0;
                        fired <= 1'b1;
                        tog   <= ~tog;
                    end else cnt <= cnt + 28'd1;
                end
            end
        end
    end
endmodule
