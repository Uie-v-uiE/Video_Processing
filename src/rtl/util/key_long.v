`timescale 1ns/1ps
// key_long —— "按住不放"检测器（与 `key_debounce` 配套，把同一个按键用出两种语义）。跑在 sys_clk 域。
//   板上只有两个键且已被"旋转 ±1°"占了（R12/R13 板级验过）⇒ 没有第三个键，短按保持原意、长按多出一个事件。
// 输出是**翻转位 tog 而不是脉冲**：消费者在 clk_pix / axi_clk，脉冲跨域会被吃掉（`ps_publish` 与 ISSUES #36 那一课）；
//   翻转位过 3 级同步后在目的域异拍还原成脉冲才安全。`fired` 保证一次按下只发一次，松手才重新武装。
// ISSUES #55 改三处：`short_pulse` **松手时**才发且只有没到过长按阈值那次才算短按（以前在按下沿发 ⇒ 每次长按必然先转
//   1°，旋转语义没变只变发的时刻；KEY2 仍吃按下沿脉冲，它要"连续反向转"，越早发越好用）；阈值 1.2 s → **0.6 s**。
module key_long #(
    parameter integer HOLD_CYC = 30_000_000,      // sys_clk 50 MHz ⇒ 0.6 s
    parameter integer ARM_CYC  = 10_000_000       // ⇒ 0.2 s：这之后 LED 亮，告诉操作者"还在计"
)(
    input  wire clk,
    input  wire rst_n,
    input  wire pressed,        // 1 = 已按下（即 key_debounce 的 ~key_stable，已去抖）
    output reg  tog,            // 每满足一次长按翻转一次
    output reg  short_pulse,    // 松手时发：这次没到长按阈值 ⇒ 算一次短按
    output reg  holding         // 按住且已过 ARM_CYC、还没到阈值：给 LED 当"正在计时"的反馈 —— 没反馈时用户只能
                                // 重按，而重按在旧模式环里会多走一格到 TEST 档（"看着像自己变成彗星图"那条）
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
