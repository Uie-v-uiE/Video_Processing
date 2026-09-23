`timescale 1ns/1ps
// src_mode —— 长按事件（sys_clk 域的翻转位）→ 片源模式（本域的四态格雷码寄存器）。
//
// 为什么要单独成模块：这段逻辑以前**写在 pl_video_top 里**，于是它没有任何台架 ——
// 而它恰好是"能不能手动锁住某一路片源"的唯一入口。第一次上板跑交接判据
// （`src/host/arb_handover_test.mjs`，#28 那块 bit）就红了：`owner_eth` 整轮没放过手，
// 而 lane30 当时只有三位，分不开"判据错 / 时基错 / 换手条件从不成立 / 模式被钉住"四种解释。
// 把仲裁看得见的输入全读回来之后一眼定死：**模式在上电自己跳到了"锁 ETH"**。
//
// 根因（一句话）：同步链的复位值必须与源头复位后的值一致，否则"上电"本身就是一次边沿。
// 旧写法 `lsync` 复位成 3'b111，而 `key_long.tog` 复位是 0 ⇒ 链里灌进的第一个 0
// 让 `lsync[1]^lsync[2]` 出现一拍为真（111→110→100→000，只有 100 那一拍不等），
// 于是一次都没按的板上白白走一步 AUTO→锁ETH，而 `sel=锁ETH` 在 `src_arb` 里是
// `force_eth=1` ⇒ owner_eth 永远为 1、"停流交回"永不发生。
//
// 这里比"把复位改成 0"再多做一步：**复位后先让链灌满 8 拍再开始比对**。
// 因为像素复位（`rst_pix_n`）不是只有上电才来一次 —— 换分辨率/掉锁都会再来一次，
// 而那时 `tog` 完全可能是 1（上一次长按留下的），单靠"复位值对齐 0"就会又白送一步。
// 台架的 T5 测的正是这一条。
//
// 模式用格雷码排（00→01→11→10→00），且下一状态**按位**写 `{mode[0], ~mode[1]}`：
// pl_video_top 里 `ms0 <= mode` 那对同步器要靠"每一位只依赖一个源触发器"才安全，
// 写成 if/(mode==…) 的比较式会被综合认成 FSM 并重编为 one-hot，实现层就把格雷码的意义抹掉了
// （实测见 ISSUES #49 与 `skill/cdc_pair_baseline_gate.md`）。
module src_mode (
    input  wire       clk,        // 像素钟 clk_pix：模式的消费者（看哪一路）在这一域
    input  wire       rst_n,
    input  wire       ltog,       // 来自 sys_clk 域的长按翻转位（`key_long` 的 tog）
    output reg  [1:0] mode        // 00 自动 / 01 锁 ETH / 11 锁 PS / 10 锁图卡
);
    localparam [1:0] M_AUTO = 2'd0, M_ETH = 2'd1, M_PS = 2'd3, M_CARD = 2'd2;

    (* ASYNC_REG = "TRUE" *) reg [2:0] lsync;
    reg        prev;              // 链尾已经认过的稳定值
    reg [2:0]  settle;            // 复位后的"灌满期"计数

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lsync  <= 3'b000;
            prev   <= 1'b0;
            settle <= 3'd0;
            mode   <= M_AUTO;
        end else begin
            lsync <= {lsync[1:0], ltog};
            if (settle != 3'd7) begin
                settle <= settle + 3'd1;
                prev   <= lsync[2];        // 灌满期里让 prev 跟住链尾，别把历史当事件
            end else if (lsync[2] !== prev) begin
                prev <= lsync[2];
                mode <= {mode[0], ~mode[1]};   // 一次翻转 = 恰好一步
            end
        end
    end
endmodule
