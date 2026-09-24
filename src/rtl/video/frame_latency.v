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
//
// ⚠ **读回口必须是"一组"而不是"五个各读各的"（ISSUES #59）**：
//   这一组数之间有恒等式 `tot ≥ c1 + c2`（c3 是"等扫描轮到它"，非负）。
//   而 `c1_*` 这些寄存器**每一轮（推流时约 9~60 次/秒）都在换**，上位机逐 lane 读要几毫秒 ⇒
//   五个数来自不同轮是完全正常的。r50 板级实测 11 组读数里 4 组破坏恒等式
//   （`build/lat_tearing_r50.txt`），而 RTL 里 `t_start ≤ t_done ≤ cyc` 是构造性成立的 ⇒
//   **错的是读法，不是硬件**。所以本模块另给一组 `q_*`：`arm` 为真的那一拍把五口**同时**抄走，
//   此后无论 live 寄存器怎么换，`q_*` 都保持同一轮的快照 ⇒ 上位机读到的一定是一组自洽的数。
//   `arm` 由 `system_top` 用"lane 选择 == 25"生成（读这一组的第一个就是 25 ⇒ 天然先武装再读其余）。
//   快照与 live 更新撞在同一拍：拿到的仍是**同一轮**的五个值 ⇒ 恒等式照样成立。
module frame_latency (
    input  wire        axi_clk,
    input  wire        axi_rst_n,
    input  wire        commit,        // 帧收完并提交（axi 域脉冲）
    input  wire        copy_start,    // 开始搬运（axi 域脉冲）
    input  wire        copy_done,     // 搬运完成（axi 域脉冲）
    input  wire        disp_sof_tgl,  // 显示帧起始，**像素域转过来的翻转位**
    input  wire        arm,           // 抄快照：lane 选择指到 25 的那一拍
    output reg  [31:0] c1_cyc,
    output reg  [31:0] c2_cyc,
    output reg  [31:0] tot_cyc,       // = c1+c2+c3（同一次配对里由拍号直接减出）
    output reg  [31:0] max_cyc,       // 历轮 tot 的最大值 —— 演示时念的就是这个
    output reg  [15:0] n_meas,        // 完整走完一轮的次数（0 ⇒ 还没量到，读数别念）
    output reg         clamped,       // 粘滞：发生过"倒挂/超长"⇒ 本会话的读数只能当**下界**
    // ---- 同一轮的五口快照（读回口只接这一组）----
    output reg  [31:0] q_c1,
    output reg  [31:0] q_c2,
    output reg  [31:0] q_tot,
    output reg  [31:0] q_max,
    output reg  [31:0] q_stat,        // { n_meas[15:0], 15'd0, clamped }
    output reg  [31:0] q_ms,          // lane24：{14'd0, pair_ok, 本轮 sticky, ms[15:0]}
    // ---- V8-5：给 OSD 的那一口（axi 域算好 ms，再按翻转位跨到像素域）----
    output reg  [15:0] lat_ms,        // 最近一轮 tot 换算成 ms，饱和 9999
    output reg         lat_valid,     // 至少完成过一次换算（0 ⇒ OSD 画 `--`）
    output reg         lat_sticky,    // 这一轮的数不可信（配对被钳位过）⇒ OSD 也要画 `--`
    output reg         lat_tog        // 每写好一次 lat_ms 翻转一次（snap_cross 的 bus_tog）
);
    localparam [31:0] CLAMP = 32'hFFFF_FFFF;

    reg [31:0] cyc;                       // 自由跑的拍号（32 bit @100 MHz ≈ 43 s 一圈）
    reg [31:0] t_commit, t_start, t_done;
    reg        have_commit, have_start, have_done;
    reg        drun;                    // 除法在跑（下面 lane24 的快照与 T13 都要读它 ⇒ 声明提前）
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

    // 一轮结束 + 这一轮的总拍数：上面那段账与下面的除法**共用这两个式子**，
    // 所以必须放在 diff() 之后、第一个用它的 always 之前
    //（xvlog 对"先于声明使用"直接报 ERROR，不会给你一个 warning 就放过）。
    wire [31:0] tot_new   = diff(cyc, t_commit);
    wire        round_end = (disp_edge && have_done);

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            cyc <= 32'd0;
            t_commit <= 32'd0; t_start <= 32'd0; t_done <= 32'd0;
            have_commit <= 1'b0; have_start <= 1'b0; have_done <= 1'b0;
            sof_sync <= 3'b0;
            c1_cyc <= 32'd0; c2_cyc <= 32'd0; tot_cyc <= 32'd0; max_cyc <= 32'd0;
            n_meas <= 16'd0; clamped <= 1'b0;
            q_c1 <= 32'd0; q_c2 <= 32'd0; q_tot <= 32'd0; q_max <= 32'd0; q_stat <= 32'd0;
            q_ms <= 32'd0;
        end else begin
            cyc <= cyc + 32'd1;
            // 快照：五口在**同一拍**抄走 ⇒ 任何时刻读到的这一组都来自同一轮（#59）。
            if (arm) begin
                q_c1   <= c1_cyc;
                q_c2   <= c2_cyc;
                q_tot  <= tot_cyc;
                q_max  <= max_cyc;
                q_stat <= { n_meas, 15'd0, clamped };
                // 第六口（lane24）：**与上面 q_tot 同一轮**的毫秒数。
                // 为什么要单独抄一份，而不是直接把 live 的 lat_ms 给 lane24：
                // lat_ms 是"最近一轮除完的商"，而 tot_cyc 是"最近一轮的拍数"，
                // 两者正常是一轮的，但**除法要 32 拍**，如果 arm 正好落在这 32 拍里，
                // 商还是上一轮的 ⇒ 拿它跟这一轮的 q_tot 比就会假红。所以在这里把
                // "这一对到底是不是一轮"一起抄下来，脚本看见 valid=0 就当没这一条（不判红也不判绿）。
                // 位序：{14'd0, pair_ok, 本轮 sticky, ms[15:0]}
                q_ms   <= { 14'd0, ~drun, lat_sticky, (drun ? 16'd0 : lat_ms) };
            end
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
                tot_cyc <= tot_new;
                // max 只认真读数：**钳位的那一轮不许污染 max** ——
                // 否则一次时序倒挂会把 max 永远钉在 0xFFFFFFFF，"最大时延"就再也读不出来了
                // （这是 tb_v90 的 T7 逼出来的，不是先想到再写的）。
                if (tot_new !== CLAMP && tot_new > max_cyc)
                    max_cyc <= tot_new;
                if ((diff(t_start, t_commit) === CLAMP) ||
                    (diff(t_done,  t_start)  === CLAMP) ||
                    (tot_new === CLAMP)) clamped <= 1'b1;
                if (n_meas != 16'hFFFF) n_meas <= n_meas + 16'd1;
                have_commit <= 1'b0; have_start <= 1'b0; have_done <= 1'b0;
            end
        end
    end

    // ================= 拍数 → ms：32 步"移位-减"的逐次除法（V8-5） =================
    // 为什么不在 OSD 里除：OSD 在**像素域**（50 MHz），而 `chars[]` 那一片本来就是这个工程里
    // 组合链最深的一段（V7.9.4 为了把它从 27 级压下来花过一整晚）。#58 那条 −5.014 的教训就是
    // "在快域里搭组合除法器"；这里改成 axi 域一轮一次的时序除法：32 拍 = 320 ns，
    // 相对一轮之间至少一帧（100 万拍）的间隔可以忽略，而且**除完才写 lat_ms** ⇒ OSD 看到的
    // 永远是一个完整、稳定的数（配 lat_tog 走 snap_cross，两帧之间不会变）。
    localparam [16:0] DIV_MS = 17'd100_000;         // 100 MHz ⇒ 1 ms = 100000 拍

    reg  [31:0] dnd;                                // 还没进位的部分（MSB 先进）
    reg  [16:0] rem;
    reg  [31:0] quo;
    reg  [5:0]  dstep;
    wire [17:0] rnext = {rem[16:0], dnd[31]};       // 移进一位后的余数（18 bit 才装得下比较）
    wire [17:0] rsub  = rnext - {1'b0, DIV_MS};     // 减法必须在 18 bit 里做：rnext 可能 ≥ 2^17
    wire        take  = (rnext >= {1'b0, DIV_MS});
    wire [31:0] q_final = {quo[30:0], take};        // 含本拍那一位的完整商（见下面收尾的注释）
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            dnd <= 32'd0; rem <= 17'd0; quo <= 32'd0; dstep <= 6'd0; drun <= 1'b0;
            lat_ms <= 16'd0; lat_valid <= 1'b0; lat_sticky <= 1'b0; lat_tog <= 1'b0;
        end else begin
            if (round_end) begin
                // 新一轮开始除。**上一轮除到一半被打断**是合法的（帧率突变），
                // 这里直接重起 ⇒ lat_ms 保持上一轮的值不动，绝不写半截数。
                dnd   <= tot_new;
                rem   <= 17'd0;
                quo   <= 32'd0;
                dstep <= 6'd0;
                drun  <= 1'b1;
            end else if (drun) begin
                dnd    <= {dnd[30:0], 1'b0};
                rem    <= take ? rsub[16:0] : rnext[16:0];
                quo    <= {quo[30:0], take};
                dstep  <= dstep + 6'd1;
                if (dstep == 6'd31) begin
                    drun <= 1'b0;
                    // 最后一位的 `take` 是**本拍**算出来的，非阻塞赋值还来不及进 quo ⇒
                    // 收尾必须用 q_final，不能用 quo（差 1 ms，而且差在"看起来对"的那一位上，
                    // 台架不加独立期望值就发现不了）。
                    // 饱和而不回卷：回卷到 0 会被读成"没有时延"，那是这块屏最不该撒的谎
                    // （同 osd 的 DROP/STALL 那一套）。
                    lat_ms    <= (q_final > 32'd9999) ? 16'd9999 : q_final[15:0];
                    lat_valid <= 1'b1;
                    // 这一轮自己钳位过 ⇒ 屏上宁可不画。`clamped` 是粘滞的（整个会话的账），
                    // 这里只用**本轮**的判据，否则一次历史倒挂会永久把 Latency 变成 `--`。
                    lat_sticky <= (tot_new === CLAMP);
                    lat_tog   <= ~lat_tog;
                end
            end
        end
    end
endmodule
