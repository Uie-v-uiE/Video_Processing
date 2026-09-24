`timescale 1ns/1ps
// V8-6：链路内时延打点 —— "一帧提交"到"这一帧开始被扫描"过了多久，分成三段量。
//
// 为什么要它：spec 的 OSD 要显示 Latency，而 `report/PERF_REPORT.md` 这一项一直是"未测"。
// 没测过的数字不上文档，所以先打点、再谈 OSD 那一格怎么写。
//
// 为什么分三段而不是一坨总数（三段成因完全不同，合起来报等于没报）：
//   c1 = commit → copy_start   等显示消隐窗口（frame_commit_lock 故意等到 quiet 才搬）
//   c2 = copy_start → copy_done 整帧搬运（DDR→帧缓存；超出消隐窗口就是 copy_overrun）
//   c3 = copy_done → 显示帧起始  搬完还要等扫描轮到它        （= tot − c1 − c2，不必单独占一口）
//   tot = commit → 显示帧起始（**先加拍再一次给出**，所以台架能验 tot == c1+c2+c3 这个恒等式）
//
// ⚠ **读数一律是"axi 拍数"，PL 里不做任何除法**。第一版（r49）在这里把拍数除以 100 换成 µs，
//   除数不是 2 的幂 ⇒ 综合架出一条组合除法器挂在 100 MHz 域，直接 WNS −5.014 ns / 96 个失败端点
//   （门禁把它拦下来了，见 ISSUES #58）。换算成时间戳是"读的人那一侧"的事：
//   `src/host/health_read.mjs` 里一个常量（100 MHz ⇒ 1 拍 = 10 ns）做完，改频率只改那一处。
//
// 口径写在明处：量的是 PL 内部（提交之后），上位机编码 / 网线 / 交换机排队一概不知道
// ⇒ 对外只能叫"**链路内时延（PL 侧）**"，不许叫端到端。
//   并且 c3 的分辨率是"一个显示帧"（60 Hz ⇒ 16.7 ms）⇒ 报数必须带 **±1 帧**。
//
// 溢出策略：**不回绕**。差值用模 2^32 减法算，一旦结果高位置 1（= 负数/时序倒挂/绕了半圈）
//   就把这一项报成 32'hFFFF_FFFF 并置 `clamped`（粘滞）。回绕会把一次很大的等待报成很小的数，
//   那是最容易骗到人、也最容易被评委当场问穿的错法。
//
// 跨域只有一个：像素域的"显示帧起始"。按本仓库规矩**只以翻转位**过来，并过 3 级 ASYNC_REG
// 再检测边沿（脉冲跨域会被吃掉 —— ISSUES #36 那一课；一级 prev 的浅同步是 #52 那类白送边沿的形状）。
module frame_latency (
    input  wire        axi_clk,
    input  wire        axi_rst_n,
    input  wire        commit,        // 帧收完并提交（axi 域脉冲）
    input  wire        copy_start,    // 开始搬运（axi 域脉冲）
    input  wire        copy_done,     // 搬运完成（axi 域脉冲）
    input  wire        disp_sof_tgl,  // 显示帧起始，**像素域转过来的翻转位**
    output reg  [31:0] c1_cyc,
    output reg  [31:0] c2_cyc,
    output reg  [31:0] tot_cyc,       // = c1+c2+c3（同一次配对里由拍号直接减出）
    output reg  [31:0] max_cyc,       // 历轮 tot 的最大值 —— 演示时念的就是这个
    output reg  [15:0] n_meas,        // 完整走完一轮的次数（0 ⇒ 还没量到，读数别念）
    output reg         clamped        // 粘滞：发生过"倒挂/超长"⇒ 本会话的读数只能当**下界**
);
    localparam [31:0] CLAMP = 32'hFFFF_FFFF;

    reg [31:0] cyc;                       // 自由跑的拍号（32 bit @100 MHz ≈ 43 s 一圈）
    reg [31:0] t_commit, t_start, t_done;
    reg        have_commit, have_start, have_done;
    (* ASYNC_REG = "TRUE" *) reg [2:0] sof_sync;
    wire disp_edge = sof_sync[1] ^ sof_sync[2];

    // 模 2^32 的差值。高位置 1 = "结果为负/绕了半圈" —— 这不是测量值，是配对坏了。
    function [31:0] diff;
        input [31:0] a, b;
        reg   [31:0] d;
        begin
            d = a - b;
            diff = d[31] ? CLAMP : d;
        end
    endfunction

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            cyc <= 32'd0;
            t_commit <= 32'd0; t_start <= 32'd0; t_done <= 32'd0;
            have_commit <= 1'b0; have_start <= 1'b0; have_done <= 1'b0;
            sof_sync <= 3'b0;
            c1_cyc <= 32'd0; c2_cyc <= 32'd0; tot_cyc <= 32'd0; max_cyc <= 32'd0;
            n_meas <= 16'd0; clamped <= 1'b0;
        end else begin
            cyc <= cyc + 32'd1;
            sof_sync <= {sof_sync[1:0], disp_sof_tgl};   // 三级：一级采样、一级稳定、一级给异或

            // ---- 三个 axi 域事件：只锁拍号，不在这里算账 ----
            if (commit) begin
                // 新的一轮：清掉上一轮没配对完的标记 ⇒ 晚到的旧事件凑不出一轮。
                // （commit_lock 里有 pending 串行化，正常走不到；这条防的是"异常时序下报假数"）
                t_commit    <= cyc;
                have_start  <= 1'b0;
                have_done   <= 1'b0;
                have_commit <= 1'b1;
            end
            if (copy_start && have_commit && !have_start) begin
                t_start    <= cyc;
                have_start <= 1'b1;
            end
            if (copy_done && have_start && !have_done) begin
                t_done     <= cyc;
                have_done  <= 1'b1;
            end

            // ---- 一轮收尾：显示帧起始到了（同步链晚 2 拍 = 20 ns，相对 ±1 帧的口径可忽略），
            //      且这一帧确实搬完过 ----
            if (disp_edge && have_done) begin
                c1_cyc  <= diff(t_start, t_commit);
                c2_cyc  <= diff(t_done,  t_start);
                // tot 由"首尾两个拍号"直接减，而不是把三段加起来：
                // 加法会把三段的 CLAMP 传染成看不懂的数，而这里要的是"这一帧总共等了多久"。
                // 台架 tb_v90 的 T2d 钉 tot == c1+c2+c3（在未钳位时），钳位时那一段单独判。
                tot_cyc <= diff(cyc,     t_commit);
                // max 只认真读数：**钳位的那一轮不许污染 max** ——
                // 否则一次时序倒挂会把 max 永远钉在 0xFFFFFFFF，"最大时延"就再也读不出来了
                // （这是 tb_v90 的 T7 逼出来的，不是先想到再写的）。
                if (diff(cyc, t_commit) !== CLAMP && diff(cyc, t_commit) > max_cyc)
                    max_cyc <= diff(cyc, t_commit);
                if ((diff(t_start, t_commit) === CLAMP) ||
                    (diff(t_done,  t_start)  === CLAMP) ||
                    (diff(cyc,     t_commit) === CLAMP)) clamped <= 1'b1;
                if (n_meas != 16'hFFFF) n_meas <= n_meas + 16'd1;
                have_commit <= 1'b0; have_start <= 1'b0; have_done <= 1'b0;
            end
        end
    end
endmodule
