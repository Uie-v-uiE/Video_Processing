`timescale 1ns/1ps
// key_long —— "按住不放"检测器（与 `key_debounce` 配套，把同一个按键用出两种语义）。
//
// 为什么要它：板上只有两个按键，而且已经被"旋转 ±1°"占了（R12/R13 板级验过）。
// 现在要加"切换片源"，没有第三个键 —— 于是短按保持原意，长按（≈1.2 s）多出一个事件。
// 输出是**翻转位 tog 而不是脉冲**：本模块跑在 sys_clk，消费者在 clk_pix / axi_clk，
// 脉冲跨域会被吃掉（这正是主线 `ps_publish` 与 ISSUES #36 那笔账的教训），
// 翻转位过 3 级同步后在目的域异拍还原成脉冲，才是安全的。
//
// 一次按下只发一次：`fired` 保证长按事件不重复，松开后才重新武装。
module key_long #(
    parameter integer HOLD_CYC = 60_000_000     // sys_clk 50 MHz ⇒ 1.2 s
)(
    input  wire clk,
    input  wire rst_n,
    input  wire pressed,        // 1 = 已按下（即 key_debounce 的 ~key_stable，已去抖）
    output reg  tog             // 每满足一次长按翻转一次
);
    localparam [27:0] HOLD = HOLD_CYC[27:0];
    reg [27:0] cnt;
    reg        fired;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 28'd0; fired <= 1'b0; tog <= 1'b0;
        end else if (!pressed) begin
            cnt <= 28'd0; fired <= 1'b0;              // 松开：重新武装
        end else if (!fired) begin
            if (cnt >= HOLD - 28'd1) begin
                cnt <= 28'd0;
                fired <= 1'b1;
                tog   <= ~tog;
            end else cnt <= cnt + 28'd1;
        end
    end
endmodule
