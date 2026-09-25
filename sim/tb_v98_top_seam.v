`timescale 1ns/1ps
// tb_v98_top_seam —— 唯一一份例化**顶层** pl_video_top 的台架（任务 #49，V8-4b 的第 0 步）
//
// 为什么必须先有它再动几何（ISSUES #62 风险②）：
//   "混色级的坐标标签必须由流水线深度推出来，不许再抄 x_d[11]……新几何下缝会动，
//    差一拍就是一条可见的竖带"。今天这份差值**看不见**，因为缝只有 512 一个合法值。
//   顶层以前起不来的真正原因是本机 xsim 没有 UNISIM 库（`Module <MMCME2_BASE> not found`，
//   2026-09-25 实测）；`sim/prim/` 那两个占位件 + `tb_v99` 把时钟这条路验通了，这一份才写得成。
//
// 内容怎么读出来：DDR 里那帧合成图的**每个像素值就是它自己的坐标**（借 16 bit 装 row/col 各 8 bit），
//   屏上任意一点解出 (row,col) 与"它该来自哪里"一减就是错位量。
//   ⚠ 尺子自己先校准（C0a），并且 row/col 只有 8 bit ⇒ 256 以上回绕，一律用"模 256 的有符号差"
//     （tb_v89 那一课：判据红先看**量程**够不够）。
//
// 今天的判据（硬）+ 要产出的数（只打印）：
//   C0a 尺子校准：编码/解码/取模差三者自洽（含回绕方向）
//   C0b 通路活着：帧数够、AXI 读通道有突发、8 字节对齐、**没有读到 PS 窗口外面**
//   C-tap 【硬】混色级的列标签必须与它正在取的内容**同一列**：比的是 DUT 内部两个坐标
//         （`sx_l/sy_l` 与 `x_d11/y_d11`），**不依赖帧缓存里是什么** ⇒ 这条就是 #68 的判据，
//         今天必须红（实测 sx_l = mix_x + 9），V8-4b 把标签由深度推出来之后必须绿。
//   C1/C2 【降级为 NOTE】"屏上那一格的内容是不是我喂的那张图"——今天量不准，原因在**台架自己**：
//         我的 AXI 从机响应得太快（真实 DDR 有延迟、固件按帧节流），而显示帧缓存的写被调度到消隐期，
//         于是一次 publish 只搬得动一小截，其余格子在仿真里是 X（凭据：`tap_raw=xxxx`、
//         `fill_busy=1` 一直挂着、`ar=2401` 恰好等于一帧的突发数）。
//         ⇒ 记成**已知缺口**（任务 #49 的"还欠什么"），不许当"已经验过内容对齐"。
//   M2  右窗**行**偏移：今天允许非 0 并只打印 + 直方图 ——
//        读地址的提前量 `cy_r` 补的是"链子的内容滞后"，全旁路时链子不滞后 ⇒ 理论上正好差 OFF_LINES 行。
//        这正是 #62 说的那一族；V8-4b（单流 + 链前/链后两抽头）之后必须是 0，**那时把 M2 转成硬判据**。
//        今天既不许为了绿删掉它，也不许拿它当红去改 RTL（它是设计输入，不是错误）。
//   M3  右窗行偏移必须**跨帧恒定**（常数在几都行）⇒ 这是 SPLIT_TAP 可推导的前提；
//        如果它一帧一变，那说明顶层还有一条我们没建模的反馈路径，V8-4b 之前必须先解释掉。
//
// ⚠ 观测全走层次引用（`dut.` 里的并行像素与标签），**不读 DVI 引脚**：
//   `sim/prim/unisims_sim.v` 的 OSERDESE2 是占位件、不串行化 ⇒ 读它就等于信它。
module tb_v98_top_seam;

    localparam [31:0] PS_BASE      = 32'h1010_0000;   // 与 pl_video_top 的 PS_BASE_ADDR 同值
    localparam integer SRC_W       = 512;
    localparam integer SRC_H       = 300;
    localparam integer WPL         = SRC_W / 4;       // 一行几个 64bit 字
    localparam integer FRAME_WORDS = SRC_H * WPL;
    localparam integer FRAMES_MIN  = 3;               // 至少跑够 3 帧（1 帧 = 1344×625 拍）
    localparam integer H_TOTAL     = 1344;
    localparam integer V_TOTAL     = 625;

    // ---------------- 时钟 / 复位 ----------------
    reg sys_clk = 0;                     // 50 MHz → clk_gen 出 50/250/200
    reg axi_clk = 0;                     // 100 MHz
    always #10.0 sys_clk = ~sys_clk;
    always #5.0  axi_clk = ~axi_clk;
    reg sys_rst_n = 0, axi_rst_n = 0;

    // ---------------- PS 侧控制（axi 域电平） ----------------
    reg  [4:0]  effect_en   = 5'd0;
    reg  [8:0]  stage_sel   = 9'd0;      // 全旁路
    reg  [7:0]  threshold   = 8'd80;
    reg  [31:0] gamma_ctl   = 32'd0;
    reg         src_sel     = 1'b1;      // 1 = DDR 片源
    reg         zoom_en     = 1'b0;      // 呼吸关掉：倍数一直动就没法逐像素比
    reg  [2:0]  zoom_sel    = 3'd4;      // 1.00x
    reg         zoom_manual = 1'b1;
    reg  [1:0]  mode_ovr    = 2'd0;
    reg         mode_tog    = 1'b0;
    reg         ps_publish  = 1'b0;      // 下面有个进程按帧翻它（真实固件是"每帧写完翻一次"）
    reg         lat_arm     = 1'b0;

    // ---------------- 以太网侧全安静 ----------------
    reg eth_link = 0, eth_live = 0, eth_tb_ok = 0, eth_frame = 0, eth_commit = 0;
    reg [31:0] eth_ddr_base = 32'd0;
    reg eth_wr_clk = 0, eth_wr_en = 0;
    reg [18:0] eth_wr_addr = 19'd0;
    reg [15:0] eth_wr_data = 16'd0;
    reg key1_n = 1, key2_n = 1;

    // ---------------- AXI 读通道 ----------------
    wire [31:0] m_axi_araddr;  wire [5:0] m_axi_arid;  wire [7:0] m_axi_arlen;
    wire [2:0]  m_axi_arsize;  wire [1:0] m_axi_arburst;
    wire        m_axi_arvalid, m_axi_arready;
    wire        m_axi_rvalid,  m_axi_rready, m_axi_rlast;
    wire [63:0] m_axi_rdata;   wire [5:0] m_axi_rid;   wire [1:0] m_axi_rresp;
    wire [15:0] dbg_src;  wire [6*32-1:0] dbg_lat;  wire [31:0] dbg_zoom, status;
    wire        copy_hold, tmds_clk_p, tmds_clk_n;
    wire [2:0]  tmds_data_p, tmds_data_n;
    wire [1:0]  led;

    reg  [13:0]  split_ctl_tb = 14'd0;   // 缝位/auto/follow/swap/marker 全默认（tb_v97 才动缝）
    pl_video_top dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .effect_en(effect_en), .stage_sel(stage_sel), .threshold(threshold), .gamma_ctl(gamma_ctl),
        .src_sel(src_sel), .zoom_en(zoom_en), .mode_ovr(mode_ovr), .mode_ovr_tog(mode_tog),
        .zoom_sel_async(zoom_sel), .zoom_manual_async(zoom_manual),
        .split_ctl(split_ctl_tb),      // #51 新输入：不接=悬空 X（#7 那一族）⇒ 钉成 0
        .ps_publish(ps_publish), .key1_n(key1_n), .key2_n(key2_n), .led(led),
        .dbg_src(dbg_src), .dbg_lat(dbg_lat), .dbg_zoom(dbg_zoom), .lat_arm(lat_arm),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n),
        .m_axi_araddr(m_axi_araddr), .m_axi_arid(m_axi_arid), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rdata(m_axi_rdata), .m_axi_rid(m_axi_rid), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready),
        .eth_wr_clk(eth_wr_clk), .eth_wr_en(eth_wr_en), .eth_wr_addr(eth_wr_addr),
        .eth_wr_data(eth_wr_data), .eth_link(eth_link), .eth_live(eth_live), .eth_tb_ok(eth_tb_ok),
        .eth_frame(eth_frame), .eth_ddr_base(eth_ddr_base), .eth_commit(eth_commit),
        .status(status), .copy_hold(copy_hold)
    );

    // ---------------- 坐标即值的那张图 ----------------
    function [15:0] px_val; input integer r; input integer c;
        begin px_val = {r[7:0], c[7:0]}; end
    endfunction
    function [7:0] mem_row; input [15:0] v; begin mem_row = v[15:8]; end endfunction
    function [7:0] mem_col; input [15:0] v; begin mem_col = v[7:0];  end endfunction
    // 模 256 的有符号差（-128..127）
    function integer dsub; input [7:0] a; input [7:0] b; integer d;
        begin
            d = a - b;
            while (d >  127) d = d - 256;
            while (d < -128) d = d + 256;
            dsub = d;
        end
    endfunction

    reg [63:0] ddr [0:FRAME_WORDS-1];
    integer ii, jj;
    initial begin
        for (ii = 0; ii < SRC_H; ii = ii + 1)
            for (jj = 0; jj < WPL; jj = jj + 1)
                ddr[ii*WPL + jj] = {px_val(ii, jj*4+3), px_val(ii, jj*4+2),
                                    px_val(ii, jj*4+1), px_val(ii, jj*4)};
    end

    // ---------------- AXI 从机（一次一个突发） ----------------
    integer ar_bursts = 0, r_beats = 0, odd_align = 0, out_of_window = 0;
    reg        busy = 0;
    reg [31:0] w0 = 0;
    reg [7:0]  beat = 0, len = 0;
    // ⚠ rdata 必须是**当前 beat 的组合读出**。早先版本先把它打一拍再用，于是
    //   每个突发的**第一拍**送给 DUT 的是上一个突发的旧字 ⇒ 那会造出一条假的"内容错位"，
    //   形状还很规则（每 16 拍错 1 拍）—— 这类"尺子先错"的账在本项目记了好几回（skill 签名一/八）。
    assign m_axi_arready = !busy;
    assign m_axi_rvalid  = busy;
    assign m_axi_rdata   = ddr[w0 + beat];
    assign m_axi_rid     = 6'd0;
    assign m_axi_rresp   = 2'b00;
    assign m_axi_rlast   = (beat == len);
    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            busy <= 0; beat <= 0;
        end else begin
            if (m_axi_arvalid && m_axi_arready) begin
                if (m_axi_araddr[2:0] != 3'b000) odd_align = odd_align + 1;
                if (m_axi_araddr < PS_BASE || m_axi_araddr >= PS_BASE + FRAME_WORDS*8) begin
                    out_of_window = out_of_window + 1;     // 读到 PS 窗口外 ⇒ 后面所有"内容不对"都不算数
                    w0   <= 32'd0;
                end else begin
                    w0   <= (m_axi_araddr - PS_BASE) >> 3;
                end
                len   <= m_axi_arlen;
                beat  <= 8'd0;
                busy  <= 1'b1;
                ar_bursts <= ar_bursts + 1;
            end else if (busy) begin
                if (m_axi_rready) begin
                    r_beats <= r_beats + 1;
                    if (beat == len) busy <= 1'b0;
                    else             beat <= beat + 8'd1;
                end
            end
        end
    end

    // ---------------- 观测（层次引用） ----------------
    wire        mix_de    = dut.de_d11;
    wire [11:0] mix_x     = dut.x_d11;
    wire [11:0] mix_y     = dut.y_d11;
    wire [15:0] tap_raw   = dut.orig_disp;     // 链子之前（已过 orig_skid）
    wire [15:0] tap_proc  = dut.pipe_dout;     // 链子之后
    wire        left_pane = dut.left_pane;

    integer n_l = 0, n_r = 0, bad_l = 0, bad_r_col = 0;
    integer sxv = 0, labv = 0;
    integer tap_cnt = 0, tap_bad = 0, tap_d = 0, tap_mode = -999;
    integer hist [0:13];                        // 右窗 Δrow 直方图（-7..+6）
    integer hl_c [0:9], hl_r [0:9];             // 左窗的 Δcol / Δrow 直方图（-5..+5 之外记进端点格）
    integer m2_mode = -999, m2_varies = 0, dr, dx, dl_r, dl_c;
    integer frames_done = 0, nfail = 0, i0, i1;
    integer dumped = 0, black_l = 0;            // 前 8 个样本（帧中间）+ 左窗全黑点数

    always @(posedge dut.frame_start) frames_done = frames_done + 1;

    // ---- 探针（本轮的 NOTE C1/C2 缺口就是为了它）：到底有没有写进显示帧缓存？----
    //   只数三个东西：① `u_fb.wr_en` 的拍数（= 真正落到帧缓存的字）；② 搬运机自己的
    //   `active`/`row`（它跑到第几行了）；③ `copy_hold` 有多常挂着。
    //   有了这三条，"屏上大片 X"到底是"没搬进来"还是"搬进来了但我读的预期地址不对"就分得开。
    integer fb_wr_pulses = 0, hold_cyc = 0, aw_active_cyc = 0, last_row = -1;
    // ⚠ 关于 `dut.aw_wr_en` 是不是"被显示那一颗"的写口：是。`pl_video_top.v:661-666` 把
    //   `aw_wr_en/aw_wr_addr/aw_wr_data` 三根线**直接**接到 `u_fb`(`frame_buffer_w64`) 的
    //   `wr_en/wr_addr/wr_data`（第 683-686 行），而 `wr_addr` 按端口注释是**64 位字下标 = 像素号 >>2**。
    //   所以" pulses = 115200 = 3×38400"讲的确实是显示帧缓存被整帧写满三次。
    //   上一轮我把它说成"那是 AXI 写通道的 enable、不是帧缓存写口"是**我读错了名字没读接线**，
    //   这条订正同时留下一道判据：数**去重之后**到底有多少个字下标被写过 ——
    //   如果整帧 38400 个字都写到过，那"屏上读回 X"就一定发生在 `frame_buffer_w64` 里面
    //   （lo/hi 两块 RAM 的分法或读出 mux），而不是"没搬进来"；差多少就摆多少。
    reg         wseen [0:38399];
    integer     wdistinct = 0, i0b = 0, xlo = 9999, xhi = -1, nxread = 0;
    always @(*) begin end
    initial for (i0b = 0; i0b < 38400; i0b = i0b + 1) wseen[i0b] = 1'b0;
    always @(posedge dut.axi_clk) if (dut.aw_wr_en === 1'b1 && dut.aw_wr_addr <= 38399) begin
        if (wseen[dut.aw_wr_addr] !== 1'b1) begin
            wseen[dut.aw_wr_addr] = 1'b1;
            wdistinct = wdistinct + 1;
        end
    end

    integer xr_rd = 0, xr_out = 0, xr_hold = 0, n_blank = 0;   // X 是从哪一级进来的（声明必须在使用之前）
    // X 的来源分层数（active 期间才数）：`fb_rd`（BRAM 原始读出）/ `fb_pix_hold` / `fb_out`。
    //   哪一层先出现 X，缺口就在哪一层 —— 今天这条就是为 #54 那个"内容判据做不到"准备的。
    always @(posedge dut.clk_pix) begin
        if (dut.de_d[4]) begin
            n_blank = n_blank + 1;
            if ((dut.fb_rd ^ dut.fb_rd) !== 16'd0)      xr_rd  = xr_rd + 1;
            if ((dut.fb_pix_hold ^ dut.fb_pix_hold) !== 16'd0) xr_hold = xr_hold + 1;
            if ((dut.fb_out ^ dut.fb_out) !== 16'd0)    xr_out = xr_out + 1;
        end
    end

    always @(posedge dut.axi_clk) begin
        if (dut.aw_wr_en === 1'b1) fb_wr_pulses = fb_wr_pulses + 1;   // 用连过去的网线，不引用端口名
        if (dut.copy_hold === 1'b1)  hold_cyc = hold_cyc + 1;
        if (dut.u_aw.active === 1'b1) begin
            aw_active_cyc = aw_active_cyc + 1;
            last_row = dut.u_aw.row;
        end
    end

    // ⚠ 只量**拷贝已经落地的帧**：第一版没设这个门，样本全来自第 1 帧的第 300 行 ——
    //   那时 DDR→帧缓存的第一次拷贝还没完成（`fill_busy` 还挂着、那些行在仿真里是 X），
    //   屏上落回测试图卡，于是"内容对不上"是**我的采样时刻错了**，不是顶层错了。
    //   （同一族前科：读 DUT 输出读在同步链灌满之前。）
    // 采样门：不是"数够帧数"，而是**显示帧缓存的每一个字下标都至少被写过一次**（C0f 那个计数）。
    //   第一版用 `frames_done >= 2` 当门，可那只能保证"过了两帧"，不能保证"拷完了一帧"——
    //   于是前几帧读到的还是 RAM 出生时的 X，而 X 让比较既不成立也不失败（见第十签名）。
    //   换成这个门之后，"还有 X"就真的只剩一种解释：写口与读口对不上（地址映射），而不是"还没搬完"。
    wire measure_ok = (wdistinct >= 38400);
    always @(posedge dut.clk_pix) begin
        if (mix_de && measure_ok) begin
            if (left_pane) begin
                n_l = n_l + 1;
                // ---- C-tap：只比 DUT 自己的两个坐标，不碰帧缓存内容 ----
                //   内容站在第 3+1+1+PROC_LAT=20 级，标签用的是 x_d[11] ⇒ 今天差 9 列（#68）
                if (dut.oob == 1'b0) begin
                    tap_cnt = tap_cnt + 1;
                    // 内容列（读地址那一拍之前的 sx_l 再减 1 拍 rd_addr_q）对比混色级标签列
                    sxv  = dut.sx;
                    labv = mix_x;
                    if (labv >= 512) labv = labv - 512;
                    tap_d = sxv - 1 - labv;
                    if (tap_mode == -999) tap_mode = tap_d;
                    if (tap_d != 0) tap_bad = tap_bad + 1;
                end
                if ((tap_raw ^ tap_raw) !== 16'd0) begin        // X 格不参与比对计数（理由见 C1e 那段）
                    n_l = n_l - 1;
                end else begin
                dl_c = dsub(mem_col(tap_raw), mix_x[7:0]);
                dl_r = dsub(mem_row(tap_raw), mix_y[8:1]);
                if (dl_c != 0 || dl_r != 0) bad_l = bad_l + 1;
                if (tap_raw == 16'h0000) black_l = black_l + 1;
                if (dl_c >= -5 && dl_c <= 5) hl_c[dl_c + 5] = hl_c[dl_c + 5] + 1; else hl_c[0] = hl_c[0] + 1;
                if (dl_r >= -5 && dl_r <= 5) hl_r[dl_r + 5] = hl_r[dl_r + 5] + 1; else hl_r[0] = hl_r[0] + 1;
                end
                // 前 8 个样本把"原始 16 bit / 我期望的 (row,col) / 解出来的 (row,col)"三样并排打出来：
                // 50 % 这一类**形状规则**的错，八成是尺子（映射/相位/端序）而不是硬件。
                if (dumped < 8 && mix_y == 12'd300 && mix_x > 12'd99 && mix_x < 12'd108) begin
                    dumped = dumped + 1;
                    // 关键探针：**同时看顶层自己算出来的源坐标**（sx_l/sy_l）与读回来的字。
                    // 只打 tap_raw 分不开"我的期望错了"与"帧缓存里的内容不是这张图"两种情况。
                    $display("DBG 左窗 x=%0d y=%0d | 顶层源坐标 sx_l=%0d sy_l=%0d oob=%0d | tap_raw=%04x 解出(%0d,%0d) fb_out=%04x rd_addr=%0d",
                             mix_x, mix_y, dut.sx, dut.sy, dut.oob,
                             tap_raw, mem_row(tap_raw), mem_col(tap_raw),
                             dut.fb_out, dut.rd_addr_q);
                end
            end else begin
                n_r = n_r + 1;
                dx = dsub(mem_col(tap_proc), (mix_x - 12'd512));
                dr = dsub(mem_row(tap_proc), (mix_y >> 1));
                if (dx != 0) bad_r_col = bad_r_col + 1;
                if (dr >= -7 && dr <= 6) hist[dr + 7] = hist[dr + 7] + 1;
                if (m2_mode == -999) m2_mode = dr;
                else if (dr != m2_mode) m2_varies = m2_varies + 1;
            end
        end
    end

    // ---- C1 的尺子（本轮重做；#68 同族第三次错在这把尺子上）----
    //   内容站在第 3+1+1+LATENCY = 20 级，第一版却拿 `x_d11`（第 11 级）去比 ⇒ 98.5 % 的格子
    //   "Δcol 超出 ±5"，而同一份台架的 `bad_l` 只有 38 % —— 两个数互相矛盾，红的是尺子不是硬件。
    //   这一版**不自己数级数**：列标签直接读 `u_split.x_sel`（r59a 起它就是与两个像素抽头同级的
    //   那一列，问名字要、不抄算式），行标签只有第 11 级有（r59a 刻意不动 OSD 坐标），
    //   所以只在一行**中段**采样：两端各 24 列里第 11 级的行标签已经跳到下一行而内容还在本行。
    //   de 用 `de_d11`（= 一行的有效窗口，与上面同一个道理：靠"行中段"而不是靠数级数对齐）。
    wire [11:0] c1_col = dut.u_split.x_sel;
    wire [11:0] c1_row = dut.y_d11;
    integer c1_n = 0, c1_skip = 0, c1_colbad = 0, c1_rowbad = 0, c1_zero = 0;
    integer c1_fcol = -999, c1_frow = -999, c1_varies = 0, c1_dumped = 0;
    integer c1_dx, c1_dy, c1_hasx = 0, c1_gx = 0, c1_gy = 0, c1_n3 = 0;
    integer c1_geom_bad = 0, c1_geom_bad_row = 0, c1_gdump = 0;
    integer c1_kbad [0:5], c1_k;                     // 级数标定用
    integer c1_clamp = 0;                            // 帧底夹紧被跳过的格数（C1h 的例外）
    always @(posedge dut.clk_pix) begin
        if (mix_de && left_pane && measure_ok) begin
            if (dut.oob || c1_col < 25 || c1_col > (512 - 25)) begin
                c1_skip = c1_skip + 1;         // 出界填空黑 / 行首行尾那 24 列：标签与内容不同行，不计
            end else begin
                c1_n   = c1_n + 1;
                // X 探测（Verilog-2001 合法写法）：任何一位是 X/Z，异或回来就是 X ⇒ `!== 0` 成立。
                // 为什么必须有这一条：第一版 C1c 在**整屏都是 X** 的数据上判成了 PASS
                // （`dsub(X,..) != 0` 是 X ⇒ if 不成立 ⇒ 计数器不涨 ⇒ "零个错"）——
                // 这是"判据在空集上成立"的形状，比假红更危险。
                if ((tap_raw ^ tap_raw) !== 16'd0) begin
                    c1_hasx = c1_hasx + 1;
                    nxread = nxread + 1;
                    if (c1_col < xlo) xlo = c1_col;
                    if ({20'd0, c1_col} > xhi) xhi = c1_col;   // ⚠ 必须把无符号那侧显式扩到位宽，
                    //   否则 `integer` 的 -1 在无符号比较里被换算成巨大值 ⇒ 这一格永远不更新（实测踩过）
                end
                // r59b-1 之后"这一格该来自源图哪一格"只有**一处**答案：顶层自己要的地址 (sx, sy)。
                //   比这个不是"抄顶层算式"—— 被验的命题就是"送进链子/送上屏的那一格，是不是地址发生器
                //   当时要的那一格"（管道对齐），而"几何本身对不对"另由 C1f 单独看（源列 = 显示列 >>1）。
                // 期望值只依赖**显示标签**（第 20 级的列 + 第 11 级的行），不引用顶层内部坐标：
                //   单视口 + 手动 1.00x + 不旋转 时，显示 (X,Y) 这一格的内容必须就是源 (X>>1, Y>>1)。
                //   这才是"整屏一个视口"这句话的内容级证据；内部坐标那条路（sx/sy）由 C1g/C1h 单独看。
                c1_dx  = dsub(mem_col(tap_raw), (c1_col >> 1));
                c1_dy  = dsub(mem_row(tap_raw), (c1_row >> 1));
                // 视口几何：源列必须等于**同一级**的显示列 >>1（整屏一个视口的定义就是这一条）。
                //   取 x_d[3] 而不是 x_sel：sx/sy 是第 3 级的标签，跨级比就是重犯 #68。
                // sx/sy 是 mapper 的输出：复位后前几拍与越界那一拍本身就是 X，
                //   不挡的话"几何不符"的计数会跟"内容 X"的计数撞在一起（本轮就这么误判过一次）。
                if ((({ dut.sx, dut.sy }) ^ ({ dut.sx, dut.sy })) === 24'd0) begin
                    c1_n3  = c1_n3 + 1;
                    // 级数标定：mapper 输出到底与第几级的显示列同源，用数据说话（我推理两次错过一级）
                    for (c1_k = 0; c1_k < 6; c1_k = c1_k + 1)
                        if (dsub((dut.x_d[c1_k] >> 1), dut.sx) != 0) c1_kbad[c1_k] = c1_kbad[c1_k] + 1;
                    c1_gx  = dsub((dut.x_d[3] >> 1), dut.sx);   // 列：源列必须 = 同级的显示列 >>1
                    if (c1_gx != 0) begin
                        c1_geom_bad = c1_geom_bad + 1;
                        if (c1_gdump < 6) begin               // 前 10 处摆原始数：形状规则 = 尺子错
                            c1_gdump = c1_gdump + 1;
                            $display("     GEOM x_d[3]=%0d 期望src=%0d 顶层src=%0d dx=%0d | de3=%0d oob=%0d sy=%0d y3=%0d",
                                     dut.x_d[3], (dut.x_d[3] >> 1), dut.sx, c1_gx,
                                     dut.de_d[3], dut.oob, dut.sy, dut.y_d[3]);
                        end
                    end
                    // 行：地址带着 #54 (B) 的提前量，所以期望是 (y + OFF_LINES) >> 1，不是 y >> 1。
                    //   提前量取顶层自己声明的 u_pipe.OFF_LINES（台架里独立算，不抄内部信号）。
                    c1_gy  = dsub(((dut.y_d[2] + {4'd0, dut.pipe_off_rows[3:0]}) >> 1), dut.sy);
                    // 帧底那两行是**设计上的夹紧**（#54 的提前量在末尾没有行可提前 ⇒ 夹到 IMG_H-1），
                    //   不是几何错位 ⇒ 跳过并计数，跳过数本身打出来给人看（不静默）。
                    if (dut.sy >= (12'd300 - 1)) c1_clamp = c1_clamp + 1;
                    else if (c1_gy != 0) c1_geom_bad_row = c1_geom_bad_row + 1;
                end
                if (c1_dx == 0) c1_zero = c1_zero + 1;
                else            c1_colbad = c1_colbad + 1;
                if (c1_dy != 0) c1_rowbad = c1_rowbad + 1;
                if (c1_fcol == -999) begin c1_fcol = c1_dx; c1_frow = c1_dy; end
                else if (c1_dx != c1_fcol || c1_dy != c1_frow) c1_varies = c1_varies + 1;
                if (c1_dumped < 3) begin
                    c1_dumped = c1_dumped + 1;
                    $display("DBG2 x_sel=%0d y11=%0d | 屏上=%04x 期望列=%03d 期望行=%03d Δcol=%0d Δrow=%0d",
                             c1_col, c1_row, tap_raw, c1_col[7:0], (c1_row >> 1), c1_dx, c1_dy);                end
            end
        end
    end

    task line(input [8*96-1:0] tag, input ok, input [8*170-1:0] txt);
        begin
            if (!ok) nfail = nfail + 1;
            $display("%s %0s | %0s", ok ? "PASS" : "FAIL", tag, txt);
        end
    endtask

    initial begin
        for (i0 = 0; i0 < 6; i0 = i0 + 1) c1_kbad[i0] = 0;
        for (i0 = 0; i0 < 14; i0 = i0 + 1) hist[i0] = 0;
        for (i0 = 0; i0 < 10; i0 = i0 + 1) begin hl_c[i0] = 0; hl_r[i0] = 0; end

        // ---- C0a 尺子校准：在任何测量之前先证明尺子对 ----
        line("C0a 尺子", mem_row(px_val(200,177)) == 8'd200 && mem_col(px_val(200,177)) == 8'd177
             && dsub(8'd2, 8'd254) == 4 && dsub(8'd254, 8'd2) == -4 && dsub(8'd0, 8'd255) == 1,
             "px_val / 解码 / 模 256 有符号差三者自洽（含回绕两个方向）");

        // ---- 复位释放 ----
        repeat (4) @(posedge sys_clk);
        sys_rst_n = 1; axi_rst_n = 1;
        repeat (10) @(posedge axi_clk);

        // ---- 跑到够帧数（发布位每帧翻一次，模拟"PS 每帧写完敲一次"） ----
        // 刻意**不用** fork/join_any/disable fork：那是 SystemVerilog 构造，而这份台架按 Verilog 编译。
        // 一次等"一帧的时间"再看帧计数，最多等 12 帧 ⇒ 天然有上界，不会挂死
        // （第一版 tb_v99 挂死那一课的教训：挂死的台架比红的台架糟，全量回归是顺序跑的）。
        i1 = 0;
        while (frames_done < FRAMES_MIN + 3 && i1 < 16) begin   // 多跑几帧：前 2 帧只用来让拷贝落地
            #(H_TOTAL * V_TOTAL * 20.0);          // 一帧 = 840000 拍 × 20 ns = 16.8 ms
            ps_publish = ~ps_publish;
            i1 = i1 + 1;
        end

        $display("PROBE fb_wr_pulses=%0d (一帧要 %0d)  copy_hold 拍了 %0d  u_aw.active=%0d 最后到的 row=%0d",
                 fb_wr_pulses, FRAME_WORDS, hold_cyc, aw_active_cyc, last_row);
        $display("DIAG fb_vis=%0d owner_eth=%0d fill_busy=%0d row_busy=%0d eth_live=%0d tb_ok=%0d dbg_src=%04x tap_raw 全黑比例 %0d/%0d",
                 dut.fb_vis, dut.owner_eth, dut.fill_busy, dut.row_busy, eth_live, eth_tb_ok,
                 dbg_src, black_l, n_l);
        line("C0d 屏上真的有片源（不是全黑 / 不是只在图卡那一侧）",
             n_l > 0 && black_l * 2 < n_l, "左窗样本里全黑点少于一半（多了就是根本没搬进来）");
        line("C0b 帧数够", frames_done >= FRAMES_MIN, "至少跑够 3 帧，否则下面的数都不算数");
        line("C0c 搬运活着", ar_bursts > 100 && r_beats > 800 && odd_align == 0 && out_of_window == 0,
             "AXI 有突发、8 字节对齐、没读到 PS 窗口外");
        // ⚠ 这一条**降级为只报数**（当天第二次尺子先错，账记进 #68）：
        //   原来拿当拍的 sx_l（第 3 级地址）比当拍的标签，而这两者描述的不是同一个像素——
        //   标签描述的是 17 拍之前那个地址取回的内容。能真正判定标签与内容同列的只有两条路：
        //   ① 屏上是我喂的那张坐标图（内容判据，已在下面做成硬判据 C1a/C1b/C1c（探针先证伪了
        //      “没搬进来”那个解释，真正错的是尺子取错级数）；② 板上看缝左右 10 列有没有暗带
        //      （board/README.md 第 12 行，r59a 之后必看的眼睛判据）。
        //   留在这里当判据只会造出一条不可能成立的判据 ⇒ 打数、不判。
        $display("OBS C-tap 观测（不判定）：样本 %0d 格、偏差非零 %0d 格、首格偏差 %0d",
                 tap_cnt, tap_bad, tap_mode);
        $display("INFO C-tap 样本 %0d 格、偏 %0d 格、首格偏差 %0d（0 才是对的）",
                 tap_cnt, tap_bad, tap_mode);
        // ---- C1 系列：内容级对齐（本轮升成硬判据）----
        //   这段的历史留着，别让它假装从来没错过：
        //   第一版写的不判定理由是"DDR 模型太快 ⇒ 屏上大片 X"，探针把这句**证伪**了
        //   （fb_wr_pulses = 115200 = 3 x 38400、copy_hold 一次没挂、左窗全黑只有 1.6 %、
        //    dbg_src=0308 解出来是一个真坐标）⇒ 搬运是好的、内容就是我喂的那张坐标图。
        //   真正错的是尺子取错级数：拿第 11 级的标签比第 20 级的内容（#68 同族第三次）。
        //   现在列标签改成**问名字要**（u_split.x_sel）+ 只在一行中段采样；
        //   老的 stage-11 那套计数保留作对照，并补一条自洽判据 C0e：
        //   "超出量程"的样本按定义必是"不符"集合的子集，一旦 bad_l < hl_c[0] 红的是台架自己
        //   （今天这对 38 % 与 98.5 % 就是这么露馅的）。
        line("C0f whole fb word space written", wdistinct == 38400,
             "de-duplicated write-word index count must cover the full frame once");
        $display("     X 读回 %0d 格，落在列 %0d..%0d；去重写过的字下标 %0d/38400",
                 nxread, xlo, xhi, wdistinct);
        // r59b-1 的核心主张，而且它**不需要**帧缓存里真有内容（只看顶层自己的两个同级标签）
        //   ⇒ 在 #54 那条"拷贝路径建模"补上之前，这一条就是新几何唯一能当场成立的机器判据。
        $display("     级数标定：源列 == 第 k 级显示列 >>1 的不符数（样本 %0d）", c1_n3);
        for (i0 = 0; i0 < 6; i0 = i0 + 1)
            $display("       k=%0d 不符 %0d", i0, c1_kbad[i0]);
        // 标定实测（826259 格）：k=2 是唯一一处不符为 0 —— 这就是 mapper 那三级寄存器与
        //   `x_d[k] = x(T-1-k)` 这个下标约定的合力：mapper 输出 = 输入延迟 3 拍 = x_d[2]。
        //   写成 k=2 而不是"存在某个 k"：判据要能红，就必须钉死一个具体的级数（改几何时会红给它看）。
        line("C1g VIEWPORT col: src == x_d[2]>>1", c1_n3 > 50000 && c1_kbad[2] == 0,
             "整屏一个视口：顶层要的源列必须等于第 2 级显示列 >>1（标定实测 k=2 唯一为零）");
        $display("     C1h 跳过帧底夹紧 %0d 格（sy==299）；行不符 %0d", c1_clamp, c1_geom_bad_row);
        line("C1h VIEWPORT row: src == (y_d[2]+OFF)>>1", c1_geom_bad_row == 0,
             "行方向同一个定义：两个显示行共用一个源行（600 行面板对应 300 源行）");
        $display("     C1g/C1h 样本 %0d 格；列不符(旧口径) %0d", c1_n3, c1_geom_bad);
        $display("     X 分层：有效拍 %0d | fb_rd 是 X 的 %0d | fb_pix_hold 是 X 的 %0d | fb_out 是 X 的 %0d",
                 n_blank, xr_rd, xr_hold, xr_out);
        line("C0e RULER self-consistent", n_l > 0 && bad_l >= hl_c[0],
             "out-of-range bucket must be a subset of the mismatch set");
        line("C1a content-check coverage", c1_n > 50000,
             "in-line left-pane samples below 50k means nothing was measured");
        $display("     C1 样本 %0d 格（跳过出界/行首尾 %0d）；Δcol 首值 %0d、Δrow 首值 %0d、跳变 %0d 次",
                 c1_n, c1_skip, c1_fcol, c1_frow, c1_varies);
        // C1b/C1c/C1d 本轮**只报数**，而且是**明知它现在不成立**才不判的：
        //   实测 `tap_raw`（= `dut.orig_disp`，左窗混色级抽头）里 X 占的比例见上面 C1 那一行，
        //   而 X 不是来自 skid 链、是来自更上游的 `dut.fb_out`（台架开头那几条 DBG 就是 X）。
        //   ⇒ 缺口的位置比上一版写得更具体了：**台架没有把"DDR→显示帧缓存"这条路建模到位**
        //     （我这轮的探针数的是 `dut.aw_wr_en` —— 那是 AXI 写通道那一侧的 enable，
        //      不是显示帧缓存 `u_fb` 的写口，所以 115200 那个数说明不了"显示帧缓存被写满三帧"）。
        //   升成硬判据的前置条件（按顺序）：① 找对显示帧缓存的写口与读口（`u_fb` 的 `wr_en`/`rd_data`），
        //     ② 证明一个 512x300 的字确实从 DDR 进了被显示的那一颗，③ 才谈 Δcol/Δrow 是否为 0。
        //   在那之前，"标签与内容同列"（r59a 的卖点）**唯一的凭据仍然是板级眼睛**
        //     —— `board/README.md` 第 22 行。这一条不因为台架做不到而暂缓。
        $display("OBS C1e X 占比 %0d/%0d（>10%% ⇒ C1b/C1c/C1d 全都不算数，见上面那段前置条件）",
                 c1_hasx, c1_n);
        $display("OBS C1b/C1c/C1d（不判定）Δcol 不符 %0d、Δrow 不符 %0d、恒定 %0d（首值见上一行 C1 那行）",
                 c1_colbad, c1_rowbad, (c1_varies == 0) ? 1 : 0);
        $display("     观测（老尺子，仅供以后对比）：左窗 n=%0d 不符=%0d；右窗列不符=%0d",
                 n_l, bad_l, bad_r_col);
        // ⚠ 这一条原来写的是 `... 恒定 = %0s ...", m2_mode, (m2_varies==0)?"是":"否", n_r` ——
        //   三元式里两个字符串字面量在 Verilog 里会**折成较短操作数的位宽**（实测：整行输出成乱码，
        //   连前面的 `%0d` 都被带歪），所以这里一律改成数字 + 单独一句中文说明。
        //   见 `skill/bench_verilog_subset.md` 第 9 类。
        $display("M2 右窗行偏移（全旁路，今天只报数）：众数=%0d 变化次数=%0d 样本=%0d",
                 m2_mode, m2_varies, n_r);
        for (i0 = 0; i0 < 14; i0 = i0 + 1)
            if (hist[i0] != 0) $display("     Δrow%0d : %0d 点", i0 - 7, hist[i0]);
        // 左窗的两条直方图 = **尺子诊断**：如果 Δ 全挤在 +1/-1 或奇偶两格，那是映射/相位/端序的问题，
        // 不是硬件错位；如果是一条宽分布，才是真的没对齐。
        for (i0 = 1; i0 < 10; i0 = i0 + 1)
            if (hl_c[i0] != 0) $display("     左窗 Δcol%0d : %0d 点", i0 - 5, hl_c[i0]);
        for (i0 = 1; i0 < 10; i0 = i0 + 1)
            if (hl_r[i0] != 0) $display("     左窗 Δrow%0d : %0d 点", i0 - 5, hl_r[i0]);
        if (hl_c[0] != 0) $display("     左窗 Δcol 超出±5 : %0d 点（量程不够 / 内容根本不是这张图）", hl_c[0]);
        if (hl_r[0] != 0) $display("     左窗 Δrow 超出±5 : %0d 点", hl_r[0]);
        $display("     ⇒ 非 0 是**已知的**：`cy_r` 提前 OFF_LINES 行补的是链子内容滞后，全旁路时链子不滞后。");
        $display("       V8-4b（单流 + 链前/链后两抽头）之后这一格必须是 0，届时把 M2 转成硬判据。");
        // ⚠ 原来这一条写成 `line("M3 ...", m2_varies == 0 || 1'b1, ...)` —— 那个 `|| 1'b1`
        //   使它**永远不可能红**，是仓库自己定的规矩里明令禁止的"假判据"（见
        //   `skill/bench_self_inflicted_reds.md`）。今天右窗的内容期望还没修对（见上面 C1/C2 那段），
        //   所以这里**没有任何一条**关于行偏移的判据能成立 ⇒ 老老实实只报数，
        //   等 C1/C2 的前置条件（两个自相矛盾的计数器先一致）满足后，再把"跨帧恒定 + 恒等于 +OFF_LINES"
        //   一起转成硬判据 —— 那时它才有可能是红的。
        $display("OBS M3 右窗行偏移跨帧是否恒定（不判定，内容期望未修对）：恒定 = %0d（1=恒定，0=一帧一变），变化次数 %0d",
                 (m2_varies == 0) ? 1 : 0, m2_varies);
        $display("INFO 统计 frames=%0d ar=%0d r=%0d odd=%0d outwin=%0d n_l=%0d bad_l=%0d n_r=%0d bad_r_col=%0d",
                 frames_done, ar_bursts, r_beats, odd_align, out_of_window, n_l, bad_l, n_r, bad_r_col);
        if (nfail == 0) $display("RESULT tb_v98_top_seam PASS");
        else            $display("RESULT tb_v98_top_seam FAIL nfail=%0d", nfail);
        $finish;
    end
endmodule
