`timescale 1ns/1ps
// V8-6：链路内时延打点 —— "一帧提交"到"这一帧开始被扫描"过了多久，分成三段量。
//
// 为什么要它：spec 的 OSD 要显示 Latency，而 `report/PERF_REPORT.md` 这一项一直是"未测"。
// 没测过的数字不上文档，所以先打点、再谈 OSD 那一格怎么写。
//
// 为什么分三段而不是一坨总数（三段成因完全不同，合起来报等于没报）：
//   L1 = commit → copy_start   等显示消隐窗口（frame_commit_lock 故意等 quiet 才搬，#33 那笔账）
//   L2 = copy_start → copy_done 整帧搬运（DDR→帧缓存；超出消隐窗口就是 copy_overrun）
//   L3 = copy_done → 显示帧起始  搬完还要等扫描轮到它
//   总 = commit → 显示帧起始（**先加拍数再换算**，不是三段各自换算后相加，见 to_us 的用法）
//
// 口径写在明处：量的是 PL 内部（提交之后），上位机编码 / 网线 / 交换机排队一概不知道，
// 所以对外只能叫"**链路内时延（PL 侧）**"，不许叫端到端。分辨率是一个 axi 拍（10 ns），
// 但 L3 的分辨率实际是"一个显示帧"（60 Hz ⇒ 16.7 ms）⇒ 报数必须带 **±1 帧**。
//
// 单位与溢出：读数按 1 µs（16 bit ⇒ 65.5 ms，够装一帧还多的等待）。
// ⚠ 到顶**钳位并置 `saturated`**，绝不回绕 —— 回绕会把一次很大的等待报成很小的时延，
//   那是最容易骗到人（也最容易被评委当场问穿）的错数。
//
// 唯一的跨域：像素域的"显示帧起始"。按本仓库的规矩先转成**翻转位**再过来
// （脉冲跨域会被吃掉 —— ISSUES #36 那一课的正面用法）；顶层例化时喂 `disp_sof_tgl`，
// 模块内部只做边沿检测，不碰源脉冲。
module frame_latency #(
    parameter integer AXI_CYC_PER_US = 100,      // fclk0 = 100 MHz ⇒ 100 拍 = 1 µs
    parameter integer SAT_US = 16'hFFFF          // 读数上限（µs）
)(
    input  wire        axi_clk,
    input  wire        axi_rst_n,
    input  wire        commit,        // 帧收完并提交（axi 域脉冲）
    input  wire        copy_start,    // 开始搬运（axi 域脉冲）
    input  wire        copy_done,     // 搬运完成（axi 域脉冲）
    input  wire        disp_sof_tgl,  // 显示帧起始，**像素域转过来的翻转位**
    output reg  [15:0] l1_us,
    output reg  [15:0] l2_us,
    output reg  [15:0] l3_us,
    output reg  [15:0] tot_us,        // 本轮总时延
    output reg  [15:0] max_us,        // 历轮最大值 —— 演示时念的是这个
    output reg  [15:0] n_meas,        // 完整走完一轮的次数（0 就说明还没量到，读数别念）
    output reg         saturated      // 粘滞：发生过钳位 ⇒ 本次会话的读数只能当下界
);
    reg [31:0] cyc;                       // 自由跑的拍号（32 bit @100 MHz ≈ 43 s 一圈）
    reg [31:0] t_commit, t_start, t_done;
    reg        have_commit, have_start, have_done;
    // 进来的 `disp_sof_tgl` 是**像素域**的异步信号 ⇒ 必须先过两级同步再做边沿检测。
    // （以前这里只有一级 prev，等于拿可能还在亚稳的值去比 —— 与 ps_publish.v 的三级写法不一致，
    //  而"同步链比源头浅"正是 #52 那一类白送一次边沿的形状。）
    (* ASYNC_REG = "TRUE" *) reg [2:0] sof_sync;
    wire disp_edge = sof_sync[1] ^ sof_sync[2];

    // 拍差用模 2^32 减法：所以计数器绕圈不影响差值（前提是单次间隔远小于 43 s，这在本设计里成立）
    function [31:0] sub32;
        input [31:0] a, b;
        begin sub32 = a - b; end
    endfunction

    // 拍 → µs，四舍五入并钳位。除数是参数（换 fclk 频率只改一处），
    // 不许用移位近似 —— 100 不是 2 的幂，近似会系统性偏小，那种偏差最难被发现。
    function [15:0] to_us;
        input [31:0] cycles;
        reg   [31:0] us;
        begin
            us = (cycles + (AXI_CYC_PER_US/2)) / AXI_CYC_PER_US;
            to_us = (us > SAT_US) ? SAT_US[15:0] : us[15:0];
        end
    endfunction

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            cyc <= 32'd0;
            t_commit <= 32'd0; t_start <= 32'd0; t_done <= 32'd0;
            have_commit <= 1'b0; have_start <= 1'b0; have_done <= 1'b0;
            sof_sync <= 3'b0;
            l1_us <= 16'd0; l2_us <= 16'd0; l3_us <= 16'd0; tot_us <= 16'd0;
            max_us <= 16'd0; n_meas <= 16'd0; saturated <= 1'b0;
        end else begin
            cyc <= cyc + 32'd1;
            sof_sync <= {sof_sync[1:0], disp_sof_tgl};   // 两级同步 + 一级给异或用的历史

            // ---- 三个 axi 域事件：只锁拍号，不在这里算账 ----
            if (commit) begin
                // 新的一轮：清掉上一轮没配对完的标记 ⇒ 晚到的旧事件不会被算进新帧。
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

            // ---- 一轮收尾：显示帧起始到了（同步后晚 2 拍 = 20 ns，相对 ±1 帧的口径可忽略），
            //      且这一帧确实搬完过 ----
            if (disp_edge && have_done) begin
                l1_us  <= to_us(sub32(t_start, t_commit));
                l2_us  <= to_us(sub32(t_done,  t_start));
                l3_us  <= to_us(sub32(cyc,     t_done));
                tot_us <= to_us(sub32(cyc,     t_commit));
                if (sub32(cyc, t_commit) > (SAT_US * AXI_CYC_PER_US)) saturated <= 1'b1;
                if (to_us(sub32(cyc, t_commit)) > max_us)
                    max_us <= to_us(sub32(cyc, t_commit));
                if (n_meas != 16'hFFFF) n_meas <= n_meas + 16'd1;
                have_commit <= 1'b0; have_start <= 1'b0; have_done <= 1'b0;
            end
        end
    end
endmodule
