`timescale 1ns/1ps
// src_life —— "此刻到底还有没有片源"这件事的**活判据**（ISSUES #94）。时钟域：clk_pix，单域，零新增异步配对。
// 单独成模块：它判的是"能不能看见画面"，出错的样子是"屏幕永久冻在最后一帧"——"永久"只有喂出"应用不再发帧了"才
// 看得见，而顶层台架（tb_video_pipeline_top）一次 75 分钟，拿它调一个 30 帧的看门狗等于用卡车送信 ⇒ 判据在 tb_v102 逐条钉。
// 它要补的三个洞（实测）：原来顶层是 `have_src = eth_link_pix | ps_src_seen`，**两个位都只置位从不清零**（见
// `pl_video_top.v:586-589`、`:494-505`）⇒ 拔网线落 SD 一直对（ETH 那路有 link_monitor 200 ms + 仲裁 20 ms 迟滞），但
// 再拔 SD 卡 ⇒ 画面**永久冻在最后一帧**，"没有片源就画图卡"进不去，卡插回去也不恢复（固件 `mounted` 不清零 = #45）。
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

    // 谁此刻真的有片源：ETH 用**活的** owner（不粘滞 ⇒ "曾经有"与"现在有"不再同形），PS 用上面的心跳判据。
    // 必须区分"故意停在最后一帧"（`src 1` 锁网络 —— COMMANDS.md 明写锁住时冻帧是语义）与"片源没了"，不许看门狗
    // 把前者误伤成后者。代价是应用侧要说清楚"我还要屏"：`frame N`/`stop` 这类用法由固件按 ~100 ms 重发同一帧
    //（`ps_keepalive`，见 main.c）—— 内容一模一样屏上无感，看门狗因此不会把"你按了 stop"读成"片源掉了"。
    // 心跳吃 ps_publish 的 new_tog ⇒ **零新增异步配对**：`cdc.rpt` 不该因为 #94 多出任何东西，多出就是接错了。
    assign have_src   = mode_ps ? ps_src_now
                                : ((mode_eth || eth_owner) || ps_src_now);
endmodule
