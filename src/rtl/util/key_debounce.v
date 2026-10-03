`timescale 1ns/1ps
// Active-low 按键消抖 + 单拍按下脉冲。定位：pl_video_top 的 u_k1/u_k2（板键 KEY1/KEY2，sys_clk 域），
// 长按那一支在 key_long。
//
// 上电武装门（r112 / ISSUES #247）：复位释放**之后**必须先连续"看见松着"满一个窗口，才开始确认按下。
//   为什么要有这一条：`key_stable` 的复位值是 1（松着）。如果复位释放那一刻线上还是低（成因待定，
//   见 #249），去抖器会把它确认成一次按下，随后线回高就是一次松手 ⇒ `key_long` 发一枚 short_pulse
//   ⇒ 角度白加 1°。这与 #52（长按同步链复位值与源头不一致 ⇒ 上电白送一次长按）是**同一个形态**：
//   事件型信号在复位释放附近被当成真事件。
//   门只吞"从没被看见松开过"那一次；一旦开过门，之后的每一次按下/松开照旧（台架 A6 钉这条）。
//   线要是上电就被按住不动：门不开、这次长按也不生效——那是有意的，与"开机不能自己改状态"一致。
module key_debounce #(
    parameter CNT_MAX = 1_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  pulse,
    output reg  key_stable  // 1 = released, 0 = pressed
);
    reg [20:0] cnt;
    reg [20:0] acnt;        // 连续"看见松着"的计数（武装用）
    reg        armed;       // 0 = 还没被证明"曾经松开过"
    reg key_sync0, key_sync1;
    reg key_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_sync0  <= 1'b1;
            key_sync1  <= 1'b1;
            key_prev   <= 1'b1;
            key_stable <= 1'b1;
            cnt        <= 21'd0;
            acnt       <= 21'd0;
            armed      <= 1'b0;
            pulse      <= 1'b0;
        end else begin
            key_sync0 <= key_n;
            key_sync1 <= key_sync0;
            pulse     <= 1'b0;

            // 武装：线连续为高满同一个窗口才开门；一旦低就清零（要求的是"看见过松手"，不是"通电过"）
            if (key_sync1) begin
                if (!armed && acnt >= CNT_MAX[20:0]) armed <= 1'b1;
                else if (!armed) acnt <= acnt + 21'd1;
            end else
                acnt <= 21'd0;

            // 门没开时不改 key_stable（cnt 允许饱和在 21 位里，开门之后再从那儿走完窗口）
            if (key_sync1 != key_stable) begin
                if (armed && cnt >= CNT_MAX[20:0]) begin
                    key_stable <= key_sync1;
                    cnt        <= 21'd0;
                end else if (cnt != CNT_MAX[20:0])
                    cnt <= cnt + 21'd1;
            end else
                cnt <= 21'd0;

            key_prev <= key_stable;
            // press edge: stable was released (1), now pressed (0)
            if (key_prev && !key_stable)
                pulse <= 1'b1;
        end
    end
endmodule
