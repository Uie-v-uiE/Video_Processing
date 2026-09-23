`timescale 1ns/1ps
// link_monitor — V7.6 (P0-A) ETH 入包链路的**硬件在线健康统计**。
//
// 为什么需要它：板上 `frame_reasm` 的 `p_good` 在 `eth_udp_video_top` 里被硬接成
// 1'b1，所以 `stat_bad` 这条路在上板时是**死的**；真正会吃掉数据的只有一处——
// CDC 写口被 `fifo_full` 挡住（`cdc_wr = (fb_wr_en||reasm_flush||flush_pend) && !fifo_full`）。
// 那一拍上的字永远消失了，之前只有"屏幕上有黑纹"这一种事后证据。
// 本模块把这件事变成**运行期可读的数字**：丢了多少字、丢过几帧、帧间隔多少、
// 多久没收到完整帧了。
//
// 时钟域：全部在 eth_rxc（gmii_rx_clk，125 MHz）域。所有输入都是**已经打过一拍
// 的信号**（frame_reasm 的输出寄存器、dc_fifo 的 wr_full），所以本模块里
// 没有组合式的多级逻辑进关键路径；每拍可能翻转的只有 drop_words 的 +1
// （使能是 2 输入与门，32bit 进位链在 7 系列的 CARRY4 上约 0.4 ns）。
//
// 输出 `lm_bus` 是**快照**而不是活计数器：它只在事件帧（frame_done / frame_abort /
// frame_err，或被 SETTLE 节流合并后的那一拍）整拍更新，平时纹丝不动。跨域方（像素域 OSD、PS 侧 GPIO）
// 用 `lm_bus_tog` 的跳变沿去**捕获**它——边沿要经过 3 级同步才到达目的域，
// 那时源总线早已稳定，所以取到的必然是一个完整的快照，不会撕烈。
// `lm_hb` 每毫秒翻转一次，只用来回答"eth_rxc 还在不在跑、跑得多快"。
// 板上实测（2026-09-23 的教训）：RTL8211 断链时**并不停供 RXC**，而是把它拉到
// ≈2.5 MHz（≈1/48）。所以本模块里所有"ms"在异常时其实是**周期数**，不是秒表读数：
// stall_ms 会以约 48 倍慢的速度往上爬，最终饱和在 0xFFFF。凡是要拿这些数字做
// **实时**判断的下游（片源仲裁），都必须先与"源时钟健康"相与 —— 见 system_top 的 eth_live。
module link_monitor #(
    parameter CLK_HZ  = 125_000_000,
    // 发布节流周期（源时钟计数）
    parameter integer SETTLE = 32,
    // 断流判据：stall_ms 超过它就不再指望 frame_done 来刷快照，改由 ms_tick 刷，
    // 这样"没有帧"这件事本身也能被下游持续看到。
    parameter [15:0] LIVE_MS = 16'd200
)(
    input  wire        clk,
    input  wire        rst_n,

    // ---- 探针（都是源模块的寄存器输出）----
    input  wire        cdc_wr_req,     // 这一拍想往 CDC 写（数据或 flush）
    input  wire        cdc_full,       // dc_fifo 满了
    input  wire        frame_done,     // 有一帧被完整接收并通过验收门
    input  wire        frame_abort,    // 有一帧字节数已到但验收失败（被作废）
    input  wire        frame_err,      // 收到一个坏包（上板时恒 0，见文件头）
    // 清零帧间隔统计。**同源域的电平**（由 eth_udp_video_top 里 3FF 同步好再送进来）。
    // 只清 gap_*：lane0/1/2/6/8/9 保持「自启动以来」的语义不变。
    input  wire        gapclr,
    input  wire [15:0] rows_missed,    // 与 frame_abort 同拍有效：本帧缺多少行
    input  wire [31:0] in_pkts,        // frame_reasm.stat_pkts
    input  wire [31:0] in_bytes,       // frame_reasm.stat_bytes

    // ---- 发布 ----
    output reg  [319:0] lm_bus,
    output reg          lm_bus_tog,
    output reg          lm_hb
);
    localparam integer TC = CLK_HZ / 1000;   // 每毫秒的周期数 = 125000
    localparam [7:0] SETTLE_V = SETTLE;
    // 分频器宽度必须由 TC 算出来。原来写死 [15:0]：125000 装不进 16 bit，
    // `ms_div == TC-1` 恒假 ⇒ ms_tick 永远不来 ⇒ ms32 / stall / gap / 心跳在板上
    // 全死。仿真里把 CLK_HZ 改成 1000（TC=1）完全看不出这个问题。
    // 取证：WARNING [Synth 8-6014] Unused sequential element ms_div_reg was removed.
    localparam integer DW = $clog2(TC + 1);

    // ---------------------------------------------------------------- 时基
    reg [DW-1:0] ms_div;
    reg        ms_tick;
    // 毫秒计数必须 32bit。原来 16bit 让 gap = ms_now − ms_last 在超过 65.5 s 的间隔上
    // 回卷：2026-09-22 拔线实验实测到 gap_max 停在 34066 ms，那是「真实计数 mod 65536」的
    // 假数；而 gap_max 是终身保持的，一次长空闲就把它永久污染，之后更大的间隔还会因为
    // 回卷而读起来更小 —— 两个方向都会说谎。仪表的数字宁可饱和也不许绕回去。
    reg [31:0] ms32;                          // 自由运行的毫秒计（32bit ⇒ 49 天不回卷）
    reg [31:0] ms_last32;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_div <= 0; ms_tick <= 0; ms32 <= 0; lm_hb <= 0;
        end else begin
            ms_tick <= 1'b0;
            if (ms_div == TC-1) begin
                ms_div <= 0;
                ms_tick <= 1'b1;
                ms32    <= ms32 + 1'b1;
                lm_hb   <= ~lm_hb;
            end else begin
                ms_div <= ms_div + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------- 计数器
    reg [31:0] drop_words;    // 被 fifo_full 吃掉的字（= 板上唯一真实的丢数据通道）
    reg [31:0] frames_bad;    // 被作废的帧
    reg [31:0] pkt_err;       // 坏包
    reg [31:0] cdc_ep;        // CDC 进入"满"状态的次数（不是拍数）
    reg [15:0] rows_miss_max; // 历次作废帧里缺行最多的一次
    reg [15:0] stall_ms;      // 距上一个 frame_done 过了多少 ms（活看门狗）
    reg [15:0] gap_last, gap_min, gap_max;
    reg [31:0] gap_sum;
    reg        have_base;     // 至少收到过 1 帧（ms_last32 基准已建立）
    reg        gap_valid;     // gap_min/gap_max 已被至少 2 帧校准
    reg        full_d;

    wire cdc_rise = cdc_full & ~full_d;
    wire [31:0] gap_raw = ms32 - ms_last32;
    // 超过 65535 ms 一律饱和：读数 0xFFFF 的含义是「至少 65.5 s」
    wire [15:0] gap_new = (gap_raw > 32'h0000FFFF) ? 16'hFFFF : gap_raw[15:0];
    // 16bit 字段一旦越过 65535 就饱和而不是回卷：健康数字回卷到 0 会被读成"没问题"，
    // 这是比少报更坏的错。
    wire [15:0] bad16 = (frames_bad > 32'h0000FFFF) ? 16'hFFFF : frames_bad[15:0];
    wire [15:0] err16 = (pkt_err     > 32'h0000FFFF) ? 16'hFFFF : pkt_err[15:0];
    wire [15:0] ep16  = (cdc_ep      > 32'h0000FFFF) ? 16'hFFFF : cdc_ep[15:0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            drop_words<=0; frames_bad<=0; pkt_err<=0; cdc_ep<=0;
            rows_miss_max<=0; stall_ms<=0;
            gap_last<=0; gap_min<=0; gap_max<=0; gap_sum<=0;
            have_base<=0; gap_valid<=0; full_d<=0; ms_last32<=0;
        end else begin
            full_d <= cdc_full;

            // 帧间隔统计清零。撤销 have_base 基准，于是下一个 frame_done 只重建基准、
            // 不会把「空闲到现在」折进间隔（与判据 D 同一套道理）。
            if (gapclr) begin
                gap_last<=0; gap_min<=0; gap_max<=0; gap_sum<=0; gap_valid<=0;
                have_base<=0;
            end

            // 每拍都可能：丢字
            if (cdc_wr_req && cdc_full) drop_words <= drop_words + 1'b1;
            if (cdc_rise)               cdc_ep     <= cdc_ep + 1'b1;

            // 每帧一次：以下互不冲突（都在同一个 always 块里，但作用于不同寄存器）
            if (frame_abort) begin
                frames_bad <= frames_bad + 1'b1;
                if (rows_missed > rows_miss_max) rows_miss_max <= rows_missed;
            end
            if (frame_err) pkt_err <= pkt_err + 1'b1;

            if (frame_done) begin
                stall_ms  <= 0;
                ms_last32 <= ms32;
                // 第一个 frame_done 只建立基准（ms_last32），量不出间隔；
                // 从第二个起才有 gap_last/min/max，否则 min 会被"上电到现在"污染。
                if (have_base) begin
                    gap_last <= gap_new;
                    gap_sum  <= gap_sum + {16'd0, gap_new};
                    if (!gap_valid) begin
                        gap_min   <= gap_new;
                        gap_max   <= gap_new;
                        gap_valid <= 1'b1;
                    end else begin
                        if (gap_new < gap_min) gap_min <= gap_new;
                        if (gap_new > gap_max) gap_max <= gap_new;
                    end
                end
                have_base <= 1'b1;
            end else if (ms_tick && stall_ms != 16'hFFFF) begin
                stall_ms <= stall_ms + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------------- 快照
    wire [4:0]  flag5   = { gap_valid,                    // bit4 帧间隔统计已可用（≥2 帧）
                           (stall_ms < LIVE_MS),         // bit3 流还活着
                           (cdc_ep != 0),                // bit2 CDC 曾经灌满
                           (frames_bad != 0),            // bit1 作废过帧
                           (drop_words != 0) };          // bit0 丢过字
    wire        upd_w = frame_done | frame_abort | frame_err
                      | (ms_tick & (stall_ms >= LIVE_MS));
    // 发布节流：两次写入之间必须留出 SETTLE 个源周期，目的域才可能"边沿到了而
    // 总线正在变"。SETTLE=32 ⇒ 256 ns，覆盖到 31 MHz 以下的目的时钟（3×40 ns 的
    // 像素时钟只需 120 ns）。节流只会**合并**发布，不会丢计数——计数器一直在走，
    // 下一拍有事件时再发一次就是新值。
    reg  [7:0]  settle;
    // 节流期间到的事件**记下来**，等窗口一过就补发。少了这个 pend，一次
    // frame_done 如果正好落在 settle 窗口里就会被整个丢掉（TB 里表现为
    // "新帧到了但 stall_ms 还停在 531"），而 stall 要等 200 ms 才会再刷。
    reg         pend_ev;
    wire        pub = (upd_w | pend_ev) && (settle == 8'd0);
    reg         upd;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            settle <= 0; upd <= 0; pend_ev <= 0;
        end else begin
            upd <= pub;
            if (pub)          begin settle <= SETTLE_V; pend_ev <= 1'b0; end
            else begin
                if (upd_w)    pend_ev <= 1'b1;
                if (settle)   settle  <= settle - 1'b1;
            end
        end
    end

    // 每个 lane 显式声明成 [31:0] 再拼：之前一行里塞两个字段时把 lane1 拼成了
    // 48 bit，整条总线错位（TB 抓到 pkts=8 读成 262144）。分开写就不可能拼错宽度。
    wire [31:0] lane0 = drop_words;                       // 丢字总数
    wire [31:0] lane1 = {err16, bad16};                   // 高 16=坏包，低 16=作废帧
    wire [31:0] lane2 = {rows_miss_max, stall_ms};        // 高 16=最大缺行，低 16=已断流 ms
    wire [31:0] lane3 = {16'd0, gap_last};                // 最近一帧间隔（ms）
    wire [31:0] lane4 = {gap_max, gap_min};               // 高 16=max，低 16=min（ms）
    wire [31:0] lane5 = gap_sum;                          // Σ间隔(ms)，均值=lane5/(frames_ok-1)
    wire [31:0] lane6 = {16'd0, ep16};                    // CDC 灌满次数
    wire [31:0] lane7 = {27'd0, flag5};                   // 标志位
    wire [31:0] lane8 = in_pkts;                          // 收到的包数
    wire [31:0] lane9 = in_bytes;                         // 收到的有效字节

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lm_bus<=0; lm_bus_tog<=0;
        end else if (upd) begin
            lm_bus <= {lane9, lane8, lane7, lane6, lane5,
                       lane4, lane3, lane2, lane1, lane0};
            lm_bus_tog <= ~lm_bus_tog;
        end
    end
endmodule
