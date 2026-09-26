`timescale 1ns/1ps
// src_life —— "此刻到底还有没有片源"这件事的**活判据**（ISSUES #94，2026-09-26 17:4x）。
//
// 为什么单独成模块：它判的是"能不能看见画面"，出错的样子是"屏幕永久冻在最后一帧"。
// "永久"只有在时间轴上喂出"应用不再发帧了"才看得见，而顶层那份台架（tb_v98）一次 75 分钟，
// 拿它调一个 30 帧的看门狗等于用卡车送信。所以判据放在 `sim/tb_v102_src_life.v`，逐条钉；
// 顶层只接线。
//
// ------------------------------------------------------------------ 它要补的三个洞（都是实测的）
// 原来顶层写的是 `have_src = eth_link_pix | ps_src_seen`，**两个位都只置位、从不清零**
// （`pl_video_top.v:586-589`、`:494-505`）。用户 2026-09-26 17:1x 在 AUTO 下实测：
//   ① 拔网线 ⇒ 立刻落到 SD（这条一直是对的：ETH 那一路有 `link_monitor` 200 ms 与仲裁 20 ms 迟滞）；
//   ② 再拔 SD 卡 ⇒ 画面**永久冻在 SD 的最后一帧**，设计里"没有片源就画测试图卡"那条根本进不去；
//   ③ 卡插回去也不恢复（固件侧 `mounted` 永不清零，那是 #45 的账，本模块不负责）。
// 三个洞：(a) PS 那一路没有任何超时；(b) 粘滞位让"曾经有"与"现在有"同形；
//   (c) 还要区分"故意停在最后一帧"（`src 1` 锁网络 —— COMMANDS.md 明写锁住时冻帧是语义）与
//      "片源没了"，不许看门狗把前者误伤成后者。
//
// ------------------------------------------------------------------ 为什么不需要新的跨域
// 心跳的**来源**是既有的发布握手：`ps_publish` 已经在 clk_pix 域里把 axi 侧的翻转位同步好，
// 并给出 `new_tog`（= "PS 刚提交了一帧"）。本模块就吃这个脉冲 ⇒ **零新增异步配对**
// （`cdc.rpt` 不该因为 #94 多出任何东西，多出来就是接错了 —— 与 #83 那条"每加一位都要单独
// 走一条同步链"的贵做法相比，这里直接量数据流本身，既省一位 GPIO 也省一次跨域账）。
// 代价是应用侧要说清楚"我还要屏"：`frame N`/`stop` 这类"故意停在一张图上"的用法，
// 由固件按 ~100 ms 重发同一帧（`ps_keepalive`，见 main.c）—— 内容一模一样，屏上无感，
// 但看门狗因此不会把"你按了 stop"读成"片源掉了"。
module src_life #(
    parameter integer CLK_HZ = 50_000_000,
    // 超时 500 ms：30 fps 源每帧 33 ms ⇒ 15 帧余量；固件的 keepalive 间隔 100 ms ⇒ 5 帧余量。
    // 短到"拔卡后半秒内画面就回到图卡"肉眼不觉得卡，长到不会把一次 SD 读超时（重试两次）
    // 误判成掉线。这个数是**量出来的**：`tb_v102` 的 S9 数从最后一个沿到超时拉高用了几个帧节拍，
    // 期望值在台架那边按手算写成字面量（不共用下面的式子 —— 共用了就会共用同一个 bug，
    // 第一版正是共用了 `TO_MS*CLK_HZ` 那个在 32 位 integer 里回绕的乘积）。
    parameter integer HB_TIMEOUT_MS = 500
)(
    input  wire        clk,             // clk_pix
    input  wire        rst_n,
    input  wire        frame_start,     // 每个显示帧一次：看门狗的计数节拍
    input  wire        ps_pub,          // 脉冲：PS 刚提交了一帧（= ps_publish 的 new_tog）
    input  wire        eth_owner,       // 仲裁此刻把屏交给 ETH（**活的**，不粘滞）
    input  wire        mode_eth,        // 锁网络：按语义保留最后一帧，不参与看门狗
    input  wire        mode_ps,         // 锁 SD：这一路有没有货只看 PS 心跳
    output wire        ps_src_now,      // PS 这一路此刻真的有片源
    output wire        have_src,        // 该不该画帧缓存（喂 fb_vis）
    output reg         ps_no_pub        // "手上没有新鲜的 PS 发布"。复位值 = **1**：上电时谁都没发过帧，
                                        //   屏上就该是图卡（与今天 `ps_src_seen` 复位为 0 同形，不改观感）
);
    // 一帧 = 1344*625 = 840_000 拍。**先除后乘**：`(CLK_HZ/1000)*HB_TIMEOUT_MS` = 25e6 不溢出，
    // 而 `HB_TIMEOUT_MS*CLK_HZ` = 2.5e10 会在 32 位 integer 里回绕 ⇒ 500 ms 变成一帧。
    localparam integer HB_CYCLES = (CLK_HZ / 1000) * HB_TIMEOUT_MS;
    localparam integer HB_FRAMES = HB_CYCLES / 840_000 + 1;

    reg [15:0] miss;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // 复位 = "没听过任何发布"：上电时帧缓存里是空的，屏上必须是图卡而不是"空帧缓存"。
            // （与今天 `ps_src_seen` 复位为 0 同形 ⇒ 上电观感一个字都不变。）
            miss <= 16'd0; ps_no_pub <= 1'b1;
        end else if (ps_pub) begin
            miss <= 16'd0;  ps_no_pub <= 1'b0;     // 沿一到立刻退回：不等下一个帧节拍
        end else if (frame_start) begin
            if (miss >= HB_FRAMES[15:0]) ps_no_pub <= 1'b1;
            else                         miss <= miss + 16'd1;
        end
    end

    assign ps_src_now = !ps_no_pub;

    // 谁此刻真的有片源：ETH 用**活的** owner（锁网络时按"锁"的语义保留），PS 用上面的心跳判据。
    assign have_src   = mode_ps ? ps_src_now
                                : ((mode_eth || eth_owner) || ps_src_now);
endmodule
