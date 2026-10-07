`timescale 1ns/1ps
// link_monitor — ETH 入包链路的硬件在线健康统计：丢字数 / 作废帧 / 帧间隔 / 断流 ms。
// 时钟域：全在 eth_rxc（gmii_rx_clk 125 MHz）；输入都是源模块**已打过一拍**的寄存器输出 ⇒ 本模块内
// 不许再插组合逻辑进关键路径。板上唯一会吃掉数据的通道是 CDC 写口被 fifo_full 挡住那一拍（p_good 在
// 顶层硬接 1，见 ISSUES #38）。lm_bus 是**快照**，跨域方用 lm_bus_tog 边沿捕获，机制见 snap_cross。
// ⚠ 断链时 RTL8211 不停供 RXC 而是拉到 ≈2.5 MHz（≈1/48）⇒ 这里所有"ms"其实是周期数、饱和在 0xFFFF，
//   下游拿它做实时判断必须先与"源时钟健康"相与（system_top 的 eth_live、snap_cross 的 hb_slow）。
module link_monitor #(
    parameter CLK_HZ  = 125_000_000,
    // 发布节流周期（源时钟计数）
    parameter integer SETTLE = 32,
    // 断流判据：stall_ms 超过它就改由 ms_tick 刷快照（"没有帧"本身也要能被下游持续看到）
    parameter [15:0] LIVE_MS = 16'd200
)(
    input  wire        clk,
    input  wire        rst_n,

    // 探针（都是源模块的寄存器输出）
    input  wire        cdc_wr_req,     // 这一拍想往 CDC 写（数据或 flush）
    input  wire        cdc_full,       // dc_fifo 满了
    input  wire        frame_done,     // 有一帧被完整接收并通过验收门
    input  wire        frame_abort,    // 有一帧字节数已到但验收失败（被作废）
    input  wire        frame_err,      // 收到一个坏包（上板时恒 0，见文件头）
    // 清零帧间隔统计：**同源域的电平**（top 里 3FF 同步好再送进来）；只清 gap_*，
    // lane0/1/2/6/8/9 保持「自启动以来」的语义不变。
    input  wire        gapclr,
    input  wire [15:0] rows_missed,    // 与 frame_abort 同拍有效：本帧缺多少行
    input  wire [31:0] in_pkts,        // frame_reasm.stat_pkts
    input  wire [31:0] in_bytes,       // frame_reasm.stat_bytes

    // 发布
    output reg  [319:0] lm_bus,
    output reg          lm_bus_tog,
    output reg          lm_hb
);
    localparam integer TC = CLK_HZ / 1000;   // 每毫秒的周期数 = 125000
    localparam [7:0] SETTLE_V = SETTLE;
    // 分频器宽度必须由 TC 算出来：原来写死 [15:0] 时装不下 125000 ⇒ `ms_div == TC-1` 恒假
    // ⇒ ms_tick 永远不来 ⇒ ms32/stall/gap/心跳在板上全死，而仿真把 CLK_HZ 改成 1000（TC=1）
    // 完全看不出。取证：WARNING [Synth 8-6014] Unused sequential element ms_div_reg was removed.
    localparam integer DW = $clog2(TC + 1);

    // 时基
    reg [DW-1:0] ms_div;
    reg        ms_tick;
    // 间隔改成"直接数"（旧的两个 32 位毫秒计相减是全设计最差 setup，见 ISSUES #95）：gap_cnt 在
    // ms_tick 加一、在 frame_done/gapclr 清零 ⇒ 间隔躺在寄存器里，组合只剩"一位判饱和 + 16 位比较"。
    // ⚠ 拍子一个没动：拆两拍的版本记账与 min/max 全对，但 lm_bus 快照在记账前就被采走 ⇒ 台架红两条。
    //   仪表的读数节拍是对外契约，不许为了时序去挪它。
    // 位宽不换理由：宁可饱和也不许绕回（16 位回卷曾把 gap_max 永久污染，且之后更大的间隔读起来反而
    // 更小 ⇒ 两个方向都说谎），但不需要 32 位：数到 0x1FFFF 钉住，gap_new 见 bit[16] 报 0xFFFF。
    reg [16:0] gap_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ms_div <= 0; ms_tick <= 0; lm_hb <= 0;
        end else begin
            ms_tick <= 1'b0;
            if (ms_div == TC-1) begin
                ms_div <= 0;
                ms_tick <= 1'b1;
                lm_hb   <= ~lm_hb;
            end else begin
                ms_div <= ms_div + 1'b1;
            end
        end
    end

    // 计数器
    reg [31:0] drop_words;    // 被 fifo_full 吃掉的字（= 板上唯一真实的丢数据通道）
    reg [31:0] frames_bad;    // 被作废的帧
    reg [31:0] pkt_err;       // 坏包
    reg [31:0] cdc_ep;        // CDC 进入"满"状态的次数（不是拍数）
    reg [15:0] rows_miss_max; // 历次作废帧里缺行最多的一次
    reg [15:0] stall_ms;      // 距上一个 frame_done 过了多少 ms（活看门狗）
    reg [15:0] gap_last, gap_min, gap_max;
    reg [31:0] gap_sum;
    reg        have_base;     // 至少收到过 1 帧（间隔基准已建立）
    reg        gap_valid;     // gap_min/gap_max 已被至少 2 帧校准
    reg        full_d;

    wire cdc_rise = cdc_full & ~full_d;
    // 两个计数器的使能各延迟一拍再入账：`u_cdc/wbin_reg -> …-> CE` 是全设计最差 setup（ISSUES #121/#124）。
    // 必须延迟**事件谓词本身**，不能延迟两个操作数——(req_d && full_d) 与 (req && full) 延一拍不等价，
    // 两信号在不同拍上各自变化时前者会漏记那一拍（台架 E1 实测 DUT 31 / 参考 32）。
    reg drop_ev_d, cdc_rise_d;
    // 间隔的读数 = 数出来的那个数（见上面 gap_cnt 那段），饱和判断只剩 bit[16] 一位
    wire [15:0] gap_new = gap_cnt[16] ? 16'hFFFF : gap_cnt[15:0];
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
            have_base<=0; gap_valid<=0; full_d<=0; gap_cnt<=0;
            // 这两个事件寄存器也补进复位（#99）：不加它们功能不差（上电第一拍起就开始跟事件），
            // 但综合会为它们各自多插一级"不复位"的推断 ⇒ Synth 8-7137 从 19 涨到 21（r86 实测）。
            drop_ev_d<=0; cdc_rise_d<=0;
        end else begin
            full_d <= cdc_full;
            drop_ev_d   <= cdc_wr_req && cdc_full;
            cdc_rise_d  <= cdc_rise;

            // 间隔计数器：清 > 帧边界 > 毫秒滴答。三者的优先关系就是语义本身
            //（"清"之后从 0 重数；帧边界这一拍的值就是上一条间隔，下一拍才归零）。
            if (gapclr)                      gap_cnt <= 17'd0;
            else if (frame_done)             gap_cnt <= 17'd0;
            else if (ms_tick && !gap_cnt[16]) gap_cnt <= gap_cnt + 1'b1;   // 一进 0x10000 就钉住

            // 帧间隔统计清零。撤销 have_base 基准，于是下一个 frame_done 只重建基准、
            // 不会把「空闲到现在」折进间隔（与判据 D 同一套道理）。
            if (gapclr) begin
                gap_last<=0; gap_min<=0; gap_max<=0; gap_sum<=0; gap_valid<=0;
                have_base<=0;
            end

            // 每拍都可能：丢字 / 进满边沿（使见上面 drop_ev_d 的说明：晚一拍入账，计数值不变）
            if (drop_ev_d)            drop_words <= drop_words + 1'b1;
            if (cdc_rise_d)           cdc_ep     <= cdc_ep + 1'b1;

            // 每帧一次：以下互不冲突（都在同一个 always 块里，但作用于不同寄存器）
            if (frame_abort) begin
                frames_bad <= frames_bad + 1'b1;
                if (rows_missed > rows_miss_max) rows_miss_max <= rows_missed;
            end
            if (frame_err) pkt_err <= pkt_err + 1'b1;

            // 记账**就在 frame_done 这一拍**：读的是上面那个计数器，所以组合只有"一位饱和 + 16 位比较"。
            // 与旧写法唯一可辨的差别：ms tick 与 frame_done 同拍时这一条间隔少计 1 ms（旧式两个自由计数
            // 相减会算进去）。tick 每 125000 拍才一次，且这是仪表的 ms 整数读数、不是数据通路 ⇒ 记下，不修。
            if (frame_done) begin
                stall_ms  <= 0;
                // 第一个 frame_done 只建立基准，从第二个起才有 last/min/max（否则 min 被"上电到现在"污染）
                if (gapclr) begin gap_last<=0; gap_min<=0; gap_max<=0; gap_sum<=0; gap_valid<=0; end else if (have_base) begin
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

    // 快照
    wire [4:0]  flag5   = { gap_valid,                    // bit4 帧间隔统计已可用（≥2 帧）
                           (stall_ms < LIVE_MS),         // bit3 流还活着
                           (cdc_ep != 0),                // bit2 CDC 曾经灌满
                           (frames_bad != 0),            // bit1 作废过帧
                           (drop_words != 0) };          // bit0 丢过字
    wire        upd_w = frame_done | frame_abort | frame_err
                      | (ms_tick & (stall_ms >= LIVE_MS));
    // 发布节流：两次写入之间必须留出 SETTLE 个源周期，目的域才可能"边沿到了而总线正在变"。
    // SETTLE=32 ⇒ 256 ns，覆盖到 31 MHz 以下的目的时钟。节流只会**合并**发布，不会丢计数。
    reg  [7:0]  settle;
    // 节流期间到的事件**记下来**、窗口一过就补发：少了这个 pend，正好落在 settle 窗口里的
    // frame_done 会被整个丢掉，而 stall 要等 200 ms 才会再刷。
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

    // 每个 lane 显式声明成 [31:0] 再拼：一行里塞两个字段曾把 lane1 拼成 48 bit、整条总线错位
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
