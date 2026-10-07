`timescale 1ns/1ps
// Active-low 按键消抖 + 单拍按下脉冲。定位：pl_video_top 的 u_k1/u_k2（板键 KEY1/KEY2，sys_clk 域），
// 长按那一支在 key_long。
//
// 上电武装门（r112 / ISSUES #247）：复位释放**之后**必须先连续"看见松着"满一个窗口，才开始确认按下。
//   它挡的是"配置那一刻线上真的低"（例如有人按住键刷 PL）那一类；
//   ⚠ 它**不是**"上电就是 1 度"的解药——那一病的因在下面的位流初值（r113 / #256），
//     台架实测：带武装门的 r112 代码在真值上电下仍然白送一枚短按（`build/evidence/r113_powup_verdict.txt`）。
//
// 位流初值（r113 / ISSUES #256 = 根因）：`system_top.v` 把这一域的 `sys_rst_n` 恒接 `1'b1`
//   ⇒ 下面那些 `if (!rst_n) ... <= 1'b1;` 全是**死支**：综合把复位摘成 FDRE，网实测到
//   `key_stable_reg`/`key_sync0_reg`/`key_sync1_reg` 的上电值是 **1'b0**（两份 dcp 各量一遍，
//   `board/output/ff_init.txt`）。于是"线上松着、寄存器说按着"，20 ms 后确认那一沿 = 一次松手
//   ⇒ 下游 `key_long` 白补一枚 `short_pulse` ⇒ 屏上 `ROT:` 就是 1°；而 `angle_reg` 的 INIT=0
//   解释了为什么每次配置都正好是 1（不是 2、3）。
//   ⇒ 修法是把上电语义**写进声明**（Vivado 认成 FF 的 INIT，xsim 也认，台架与硬件同源），
//     不依赖一条根本不存在的复位。将来若真给这一域接上 POR，这里与 `if(!rst_n)` 两处同向，不用改。
module key_debounce #(
    parameter CNT_MAX = 1_000_000
)(
    input  wire clk,
    input  wire rst_n,
    input  wire key_n,
    output reg  pulse,
    output reg  key_stable = 1'b1  // 1 = released, 0 = pressed —— 这个初值就是位流上电值，见文件头 r113
);
    reg [20:0] cnt;
    reg [20:0] acnt;        // 连续"看见松着"的计数（武装用）
    reg        armed;       // 0 = 还没被证明"曾经松开过"
    reg key_sync0 = 1'b1, key_sync1 = 1'b1;   // 上电=松着（与 if(!rst_n) 那条同向）
    reg key_prev  = 1'b1;

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
