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
//   C1/C2 【#78 之后已经能用了】"屏上那一格的内容是不是我喂的那张图"。
//         以前它全程在数 X（两个真 bug：① split_ctl 加宽到 19 位后台架还接 14 位 ⇒ 高 5 位是 Z
//         ⇒ fit_en 是 Z ⇒ inv_used/sx/sy/rd_addr 全 X；② DDR 初始化那条"一行里四次调用函数再拼接"
//         在 xsim 里低 40 位给 X）。修完之后实测：窗口内 X 占比 0/826259、**Δcol 不符 0**。
//         剩下的 Δrow 不符 3704 也已定性（01:58）：**全部是 +43 = 299 的低 8 位**，
//         即"一帧头 OFF_LINES 行里行环还装着上一帧尾"——跳过条件由 u_pipe.OFF_LINES 推出、
//         跳过的格数照 print，于是 **C1d 也是硬判据**。屏顶那几行归眼睛（板级项），台架不粉饰。
//         —— 全部细节与凭据：report/ISSUES.md #78、sim/v98_ruler_fix_verdict.txt。
//         #97 第四笔（09-27 10:4x）把这句话改了两处：C1h 的期望式子带上帧头绕回，
//         C1d-b 从"跳过的那几行必须等于 299（病灶）"升级成"必须等于本行自己要的那一源行"，
//         另加两条覆盖地板（c1_wrapn / c1_ring_n）—— 屏顶那几行从此台架也能判，眼睛只复核。
//   M2  右窗行偏移：**今天众数已经是 0**（V8-4b 预言对了），但一帧之内还会变几千次
//        ⇒ 转硬判据之前要先解释那几千次（见 #78 剩下的第 5 条）。
//   M3  右窗行偏移必须**跨帧恒定**（常数在几都行）⇒ 这是 SPLIT_TAP 可推导的前提；
//        如果它一帧一变，那说明顶层还有一条我们没建模的反馈路径，V8-4b 之前必须先解释掉。
//   ⚠ 自校准的形状（#78 的教训）：C0a 只验"函数对不对"，验不到"写进数组之后对不对"——
//     当年函数是好的、数组是 X，C0a 一路 PASS。所以多了 C0a2 **模型回读**。
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

    // #94 之后**必须有**这一条，否则整份台架会被自己的新判据污染：
    //   `have_src` 现在是"最近 30 帧收到过一次发布"的活判据（`src_life`，500 ms @ 16.8 ms/帧），
    //   而下面 C2 的八档扫描要跑 40+ 帧 ⇒ 不持续敲发布位，扫到中途屏幕就**正确地**落到测试图卡。
    //   18:11 那一轮就是这样：code 5/6/7 采到的"不符"其实是图卡的渐变色（`orig==proc`、
    //   row/col 全不对就是它的形状），不是显存内容 —— 红的是激励缺心跳，不是几何。
    // ⚠ 节拍必须**与 frame_start 同拍无关**：19:4x 第一版我把翻转发在 `@(posedge dut.frame_start)`
    //   上，结果八档**全部**变脏（连原来干净的 0.25x~0.75x 也脏）—— 因为 `pub_consume` 就在
    //   frame_start 那一拍评估，发布沿与消费同拍会改变拷贝的相位/重叠，而这份台架的 AXI 从机
    //   模型对"拷贝怎么起头"是敏感的（板上 30 fps 连续拷贝没问题，见 #53/#32 的板级复验）。
    //   所以现在照抄原来的时间基准写法（`#(一帧)`），只是不再跑 16 次就停：每 4 帧翻一次，
    //   与固件 `ps_keepalive()` 的 100 ms 同量级、远快于 30 帧的看门狗。
    initial forever #(H_TOTAL * V_TOTAL * 20.0 * 4) begin
        ps_publish = ~ps_publish;
    end

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

    // 双线性开关接到台架的**激励**上（端口那里 #88 的来龙去脉只讲一遍，见下面例化处）。
    // ⚠ #92：C2b 问的是"这一格解出来是不是定义要的那个源列"，而双线性**按定义**会把 `(sx,sy)`
    //   与它的右邻/下邻混成一格 —— 混出来的 16 位 tag 谁都不是。bilin=1 时它在 inv=1023 那档
    //   给出 68920/77400 = 89 % 的"inbad"，那不是错位，是**尺子把插值当成了 bug**
    //   （bilin=0 ⇒ 最近邻 ⇒ C2b 才成立）。所以扫描段把它钉成 0，别再去松判据。
    reg         bilin_en_tb = 1'b1;
    // ⚠ #78：这份 tie 必须是 **19 位**。r62（V9）把 `split_ctl` 从 14 位加宽到 19 位时
    //   只改了综合树里的两个顶层（`ports_check` 抓到了 `pl_demo_top`），**台架不在综合树里 ⇒ 没人抓它**：
    //   14 位的 tie 接到 19 位端口，xsim 把高位填成 Z ⇒ `gp[18:14]=zzzzz` ⇒ `fit_en` 是 Z ⇒
    //   `inv_used = fit_en ? inv_fit : inv_scale` 出 X ⇒ sx/sy/rd_addr 全 X ⇒ **fb_rd 100% 是 X**
    //   （证据 `[Xborn3] gp(19位几何)=zzzzz00000000000000`）。与上面那一条是同一个洞的两面。
    reg  [18:0] split_ctl_tb = 19'd0;   // 缝位/auto/follow/swap/marker/旋转三位/fit 全默认
    pl_video_top dut (
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n), .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .stage_sel(stage_sel), .threshold(threshold), .gamma_ctl(gamma_ctl),
        .src_sel(src_sel), .zoom_en(zoom_en), .mode_ovr(mode_ovr), .mode_ovr_tog(mode_tog),
        // ⚠ #88 的**根因就这一行**：这个输入原来在台架里**根本没接**（#83 加端口时只改了
        //   `pl_demo_top`，而门禁第 14 项的端口审计当时只看 `src/rtl`，台架不在里面）⇒ 悬空成 Z
        //   ⇒ 顶层 `kx/ky` 是 X ⇒ `bilin_lerp` 输出 X ⇒ 结果缓冲每一格都被写成 X ⇒ `fb_rd` 在
        //   1843200 个有效拍里 X 了 1843188 个（实测，见 [Xborn5]/[Xborn6]）——于是 C1e 与它下游的
        //   C1c/C0d/C0e 一起红了好几天，而**症状读起来像"顶层内容通路坏了"**。
        //   现在接台架的 `bilin_en_tb`：默认 1 = 双线性开（与固件默认一致），扫描段改成 0 的理由在
        //   那个 reg 上面（一句话：C2b 量的是几何，双线性按定义会把两格混成一格）。
        .bilin_en_axi(bilin_en_tb),
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
    // ⚠ #78：端口用定宽向量（不是 `integer`）只是**顺手统一写法**，真因是另一件事：
    //   在**一条表达式里连调四次同一个 function 再拼接**，xsim 在这个大台架里给出
    //   `ddr[0]=000300xxxxxxxxxx`（低 40 位 X）；拆成四个临时寄存器再拼（见下面的 initial）就干净了。
    //   同样的写法在 20 行的隔离实验 `sim/xtest.v` 里是**干净的**（三种写法都对）⇒ xsim 的根因没查出来，
    //   但症状与修法都实测过。**教训不是"别那样写"，而是下面那条**：
    //   尺子的模型必须在**初始化之后回读一格**（C0a 现在这么做了）——
    //   旧版 C0a 只直接调 `px_val(200,177)` 验函数本身，于是"函数对、数组是 X"这种形状它看不见。
    function [15:0] px_val; input [31:0] r; input [31:0] c;
        // ⚠ 位 15 **钉成 1**（#92 收尾，2026-09-26 17:3x）。原来写的是 `{r[7:0],c[7:0]}`，
        //   于是源格 (0,0)、(256,0) 这些 `(row mod 256)==0 && col==0` 的格子编出来就是 **16'h0000**
        //   —— 而面板级那把尺子（C3）判"这一格在不在画面里"用的就是"是不是全黑"：
        //   图案自己的黑格与"画面外的黑"在引脚上**长得一模一样**，于是 0.50x/0.75x 各有两行
        //   的左沿量到"晚两列"（`C3DEV` 报的正是 `prow=406/407`、`461` 这种成对行 = 一个源行），
        //   红的是尺子的前提，不是硬件。位 15 当"非黑"标志 ⇒ 全帧 300×512 格没有一格是黑的，
        //   黑色重新变成"画面外"的唯一签名。
        //   代价：行标签从 8 位变 7 位 ⇒ `mem_row` 是 `row mod 128`。这不影响这些判据要抓的东西
        //   （它们全是"小偏移"检测：Δrow 差 1/2/4 行照样看得见），但**所有绝对行号期望都要按
        //   mod 128 写**（299 → 43 恰好与原来同值；200 → 72）。C0a 现在直接把"没有一格是黑的"
        //   当成一条判据来跑，不再靠注释。
        begin px_val = {1'b1, r[6:0], c[7:0]}; end
    endfunction
    function [7:0] mem_row; input [15:0] v; begin mem_row = v[14:8]; end endfunction
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
    integer ii, jj, c0a3_r, c0a3_c, c0a3_black;
    reg [15:0] p3, p2, p1, p0;
    initial begin
        for (ii = 0; ii < SRC_H; ii = ii + 1)
            for (jj = 0; jj < WPL; jj = jj + 1) begin
                // ⚠ #78：这里先从函数里取到**各自的临时寄存器**再拼 ——
                //   一行里连调四次同一个函数时，xsim 在这个大台架里给出的低 40 位是 X
                //   （同样写法在 20 行的隔离实验 `sim/xtest.v` 里是干净的 ⇒ 结论：还没找到真因，
                //    见 report/ISSUES.md #78 的"未定论"段）。
                p3 = px_val(ii, jj*4+3); p2 = px_val(ii, jj*4+2);
                p1 = px_val(ii, jj*4+1); p0 = px_val(ii, jj*4);
                ddr[ii*WPL + jj] = {p3, p2, p1, p0};
                if (ii == 0 && jj == 0)
                    $display("[tb_v98_top_seam.v:151] [Xborn0] 初始化现场 p3=%h p2=%h p1=%h p0=%h -> ddr[0]=%h",
                             p3, p2, p1, p0, ddr[0]);
            end
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

    // ---------------- P1：链子在第一级（blur）到底有没有"武装 / 多跳"过（#92 第四笔的顶层追问） ----------------
    // 台架 `tb_v89` 里四个窗口级 + 整链的逐列恒等已经全绿，可顶层 C2 的 484 一模一样还在 ⇒
    // 病灶要么在顶层喂给链子的**标签级**（链子吃 `de_d[3]/x_d[3]`，行环吃 `de_d[5]/x_d[5]`），
    // 要么在混色级怎么消费链子的输出。先把"有没有武装/有没有跳"数出来——
    // 这是三行代码换一个 40 分钟周期，比继续推便宜。计数不判红，判据等数字出来再写。
    integer p_arm = 0, p_flush = 0, p_piped = 0, p_mixde = 0, p_runmax = 0, p_runmin = 99999;
    always @(posedge dut.clk_pix) begin
        if (dut.u_pipe.u_blur.de_in === 1'b1 && dut.u_pipe.u_blur.x_in === 12'd1023) p_arm = p_arm + 1;
        if (dut.u_pipe.u_blur.line_end === 1'b1)                                     p_flush = p_flush + 1;
        // v5 的判据是"行尾那一拍 run 正好等于 H_ACTIVE(=1024)"。顶层每行到底数出几个有效像素，
        // 这里当场量出来：min/max 都是 1024 ⇒ 会武装；不是 ⇒ 差几个就是链子的 de 窗与 H_ACTIVE
        // 的差（这一条数就是下一次该怎么写 `owed` 的唯一依据，不许靠猜）。
        if (dut.u_pipe.u_blur.de_d1 === 1'b1 && dut.u_pipe.u_blur.de_in === 1'b0) begin
            if (dut.u_pipe.u_blur.run > p_runmax) p_runmax = dut.u_pipe.u_blur.run;
            if (dut.u_pipe.u_blur.run < p_runmin) p_runmin = dut.u_pipe.u_blur.run;
        end
        if (dut.pipe_de === 1'b1)                                                    p_piped = p_piped + 1;
        if (dut.de_d[11] === 1'b1)                                                   p_mixde = p_mixde + 1;
    end

    // ---- #78 ⓪：先找 X 的**出生地**，再谈机制（每层都带分母，不许只看"有没有"）----
    //   四层：从机送出的字 → 写进 fb 的字 → fb 阵列本身 → 读出的字。
    //   阵列里就有一堆 X ⇒ 病在写侧；阵列干净而读出是 X ⇒ 病在读侧（撞沿 / 地址是 X / 选块）。
    integer xb_rvalid = 0, xb_rdataX = 0, xb_wren = 0, xb_wdataX = 0;
    integer xb_rdX = 0, xb_addrX = 0, xb_arrX = 0, xb_firstX = -1, xb_k, xb_cyc = 0;
    reg     xb_done = 0;
    always @(posedge axi_clk) begin
        if (m_axi_rvalid) begin
            xb_rvalid = xb_rvalid + 1;
            if ((m_axi_rdata ^ m_axi_rdata) !== 64'd0) xb_rdataX = xb_rdataX + 1;
            // 头 6 拍把"索引三件套 + 读出来的字"并排打出来：X 是在**索引**上还是在**数组**里，一眼分得开
            if (xb_rvalid <= 6)
                $display("[Xborn1] rvalid#%0d w0=%0d beat=%0d len=%0d rdata=%h ddr[%0d]=%h",
                         xb_rvalid, w0, beat, len, m_axi_rdata, w0 + beat, ddr[w0 + beat]);
        end
        if (dut.aw_wr_en) begin
            xb_wren = xb_wren + 1;
            if ((dut.aw_wr_data ^ dut.aw_wr_data) !== 64'd0) xb_wdataX = xb_wdataX + 1;
            if (xb_wren <= 3)
                $display("[tb_v98_top_seam.v:234] [Xborn2] fb写#%0d addr=%0d data=%h", xb_wren, dut.aw_wr_addr, dut.aw_wr_data);
        end
    end
    always @(posedge dut.clk_pix) begin
        if (dut.de_d[5]) begin
            xb_cyc  = xb_cyc + 1;
            if ((dut.u_bilin.addr_q ^ dut.u_bilin.addr_q) !== 19'd0) xb_addrX = xb_addrX + 1;
            if ((dut.fb_rd   ^ dut.fb_rd)       !== 16'd0) xb_rdX   = xb_rdX   + 1;
        end
        if (!xb_done && frames_done >= 4) begin
            xb_done = 1;
            for (xb_k = 0; xb_k < 32768; xb_k = xb_k + 1)
                if ((dut.u_bilin.u_fb.lo[xb_k] ^ dut.u_bilin.u_fb.lo[xb_k]) !== 64'd0) begin
                    xb_arrX = xb_arrX + 1;
                    if (xb_firstX < 0) xb_firstX = xb_k;
                end
            for (xb_k = 0; xb_k < 8192; xb_k = xb_k + 1)
                if ((dut.u_bilin.u_fb.hi[xb_k] ^ dut.u_bilin.u_fb.hi[xb_k]) !== 64'd0) begin
                    xb_arrX = xb_arrX + 1;
                    if (xb_firstX < 0) xb_firstX = 32768 + xb_k;
                end
            $display("[tb_v98_top_seam.v:255] [Xborn] 从机 rvalid=%0d 其中字含X=%0d | fb 写=%0d 拍 其中数据含X=%0d",
                     xb_rvalid, xb_rdataX, xb_wren, xb_wdataX);
            $display("[tb_v98_top_seam.v:257] [Xborn] 阵列（lo 32768 + hi 8192 = 40960 字）里含 X 的字数=%0d，首个下标=%0d",
                     xb_arrX, xb_firstX);
            $display("[tb_v98_top_seam.v:259] [Xborn] 有效拍=%0d：rd_addr 是 X 的=%0d，fb_rd 是 X 的=%0d",
                     xb_cyc, xb_addrX, xb_rdX);
            // 几何那一路的 X 是分开的第二个症状（地址 X ⇒ 读哪儿都是 X）：把源头三格一起念出来
            $display("[tb_v98_top_seam.v:262] [Xborn3] gp(19位几何)=%b inv_used=%d sx=%d sy=%d oob=%b rd_addr=%d",
                     dut.gp, dut.inv_used, dut.sx, dut.sy, dut.oob, dut.u_bilin.addr_q);
            // r69 之后新加的一条（#88 的 X 到底生在哪）：阵列已证干净（上面那条"含 X 的字数"只报填充区），
            // 而屏上内容仍是 X ⇒ 嫌疑只剩"**这一格该显示谁**"那一束控制位。全部用 %b：X 会直接显形。
            //   fb_vis = (mode_card ? 0 : (mode_eth|mode_ps) ? 1 : src_use) && have_src
            //   ⇒ mode 里有一位是 X，这三个 compare 就都是 X，pix_raw 整条流跟着变 X。
            $display("[tb_v98_top_seam.v:266] [Xborn4] 归属链 mode=%b owner_eth=%b owner_pix=%b src_use=%b eth_link_pix=%b ps_now=%b have_src=%b fb_vis=%b | fb_out=%h orig_disp=%h",
                     dut.mode, dut.owner_eth, dut.owner_eth_pix, dut.src_use, dut.eth_link_pix,
                     dut.ps_src_now, dut.have_src, dut.fb_vis, dut.fb_out, dut.orig_disp);
            // 第二层（同一次运行里接着往下看一格）：`u_bilin` 的**写**把 X 存进结果缓冲时，
            //   读口才"干净阵列读出 X"—— 所以要把写侧的四元组与插值输入一起摆出来。
            //   为什么必须有这一层：帧缓存阵列已证干净（上面那条只报填充区），而 fb_out 是 X，
            //   中间只剩 `tap_hold`/`res` 两块 RAM 与 `bilin_lerp` ⇒ 谁的 X 一测就分得开。
            $display("[tb_v98_top_seam.v:271] [Xborn5] mapper fx=%h fy=%h sx=%d sy=%d oob=%b | bilin addr_q=%d fb_word=%h tap_r=%h res_q=%h lerp=%h v_d2=%b asm_d2=%b",
                     dut.zfrac_x, dut.zfrac_y, dut.sx, dut.sy, dut.oob,
                     dut.u_bilin.addr_q, dut.u_bilin.fb_word, dut.u_bilin.tap_r,
                     dut.u_bilin.res_q, dut.u_bilin.lerp_pix, dut.u_bilin.v_d2, dut.u_bilin.asm_d2);
            // 第三层：四个抽头逐个摆出来（哪个先 X，缺口就在哪一行的哪一路）。`fb_word` 已证来自干净阵列，
            //   所以 X 只可能生在 a_hold/b_hold 的**锁存时机**、tap_hold 的读回、或 lerp 的加权上。
            $display("[tb_v98_top_seam.v:277] [Xborn6] w_a=%d w_b=%d lane=%d | a_hold=%h b_hold=%h | p00=%h p10=%h p01=%h p11=%h | oob_d2=%b kx=%b ky=%b bilin_en=%b",
                     dut.u_bilin.w_a, dut.u_bilin.w_b, dut.u_bilin.lane,
                     dut.u_bilin.a_hold, dut.u_bilin.b_hold,
                     dut.u_bilin.p00_y0, dut.u_bilin.p10_y0c, dut.u_bilin.p01, dut.u_bilin.p11,
                     dut.u_bilin.oob_d2, dut.u_bilin.kx_d2, dut.u_bilin.ky_d2, dut.u_bilin.bilin_en);
        end
    end

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
                dl_r = dsub(mem_row(tap_raw), mix_y[8:1] & 8'h7F);   // #92：行标签现在是 mod 128
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
                    $display("[tb_v98_top_seam.v:353] DBG 左窗 x=%0d y=%0d | 顶层源坐标 sx_l=%0d sy_l=%0d oob=%0d | tap_raw=%04x 解出(%0d,%0d) fb_out=%04x rd_addr=%0d",
                             mix_x, mix_y, dut.sx, dut.sy, dut.oob,
                             tap_raw, mem_row(tap_raw), mem_col(tap_raw),
                             dut.fb_out, dut.u_bilin.addr_q);
                end
            end else begin
                n_r = n_r + 1;
                dx = dsub(mem_col(tap_proc), (mix_x - 12'd512));
                dr = dsub(mem_row(tap_proc), (mix_y >> 1) & 8'h7F);
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
    integer c1_pbad [0:5];                           // C1i：读口的相位量与第 k 级标签不符数（r63/#79）
    integer c1_kn, c1_ktrue;                         // "几何 0 不符"的级数有几个、是哪一级
    integer c1_clamp = 0;                            // 期望落在"设计上夹紧那两行"的格数（#97 第四笔之后也照判，见下）
    integer c1_adv = 0, c1_exp = 0, c1_wrapn = 0;     // C1h 的期望行：先算请求行，再按帧头绕回的定义折一次；c1_wrapn = 落在绕回窗里的格数（地板用）
    integer c1_ring  = 0;                            // 行环热身被跳过的格数（#54 第 5 条，见采样处注释）
    integer c1_ring_n = 0;                           // 其中"已过了开机那两帧、可正名"的格数（地板用）
    integer c1_ring_unexpl = 0;                      // 被跳过的格子里"内容不是本行自己要的那一源行"的个数（必须 0）
    localparam integer C1_WARM = 2;                  // = pl_video_top 的 BILIN_ROWS：乒乓缓冲在帧首多出来的那一对
    // #54 第 5 条的仪器（Δrow ≠ 0 到底长什么样）：按 Δrow 值分 10 桶 + 按列位置分 16 桶
    integer c1_rdh [0:9], c1_rdbk [0:15], c1_rdump;
    always @(posedge dut.clk_pix) begin
        if (mix_de && left_pane && measure_ok) begin
            if (dut.oob || c1_col < 25 || c1_col > (512 - 25)) begin
                c1_skip = c1_skip + 1;         // 出界填空黑 / 行首行尾那 24 列：标签与内容不同行，不计
            end else if (c1_row < (dut.pipe_off_rows + C1_WARM)) begin
                // #54 第 5 条（01:58 定性）：这不是尺子的错，也不是地址的错，是**行环的开机热身**。
                //   原图抽头走 `raw_line_delay #(.LINES(RAW_LINES = u_pipe.OFF_LINES))`：
                //   一帧的头 OFF_LINES 个显示行里，环里装的是**上一帧尾部**那一行。旧状下那个地址被
                //   夹到 299，编码只剩低 8 位 ⇒ 解出来正好是 43 = 0x2B；实测 3704 个 Δrow≠0 的样本
                //   **全部**是 +43、且只出现在 `y11 = 0..3`（ROWMIX 那三行分布：列上均匀、值上单一）。
                //   ⇒ 跳过 C1d 并**数出来**（与 oob / 行首尾 / 帧底夹紧同一族：例外要说得清、要见数）。
                // #97 第四笔把这一族的**内容**改了定义，于是这里的例外从"解释成上一帧帧底"升级成
                //   "逐格正名 = 本行自己要的那一源行"：环深 8、`rslot = y−4 mod 8`，而帧尾那
                //   OFF_LINES 行（596..599）正好落在 4..7 号槽 ⇒ 帧头 0..3 读到的就是**上一帧的
                //   帧尾请求**，而绕回之后的那个请求行是 0,0,1,1 —— 与 `y>>1` 逐格相等。
                //   （这条几何关系是有条件的：`2*IMG_H mod 环深 == 0`，600 mod 8 = 0 才成立。
                //    哪天行数或 RAW_LINES 变了，这一条会红，而不是悄悄变成"又热了一次身"。）
                c1_ring = c1_ring + 1;
                // r63/#79 的规矩不变：例外必须**说得出内容是什么**才许跳过。变的是那句话的内容 ——
                //   旧版"必须等于 43（=299 的低 8 位）"钉的是**病灶**，修好之后它反而会红。
                //   开机头两帧不在话下（环里还是初值 0，那是"没数据"不是"数据错"）⇒ 只从第三帧起判，
                //   并另记一个可判格数当覆盖地板，否则这条又变成"空集上成立"（#78 同一族）。
                if (frames_done >= 3) begin
                    c1_ring_n = c1_ring_n + 1;
                    if (mem_row(tap_raw) !== ((c1_row >> 1) & 8'h7F)) c1_ring_unexpl = c1_ring_unexpl + 1;
                end
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
                c1_dy  = dsub(mem_row(tap_raw), (c1_row >> 1) & 8'h7F);   // 同上：小偏移检测不受影响
                // 视口几何：源列必须等于**同一级**的显示列 >>1（整屏一个视口的定义就是这一条）。
                //   取 x_d[3] 而不是 x_sel：sx/sy 是第 3 级的标签，跨级比就是重犯 #68。
                // sx/sy 是 mapper 的输出：复位后前几拍与越界那一拍本身就是 X，
                //   不挡的话"几何不符"的计数会跟"内容 X"的计数撞在一起（本轮就这么误判过一次）。
                if ((({ dut.sx, dut.sy }) ^ ({ dut.sx, dut.sy })) === 24'd0) begin
                    c1_n3  = c1_n3 + 1;
                    // 级数标定：mapper 输出到底与第几级的显示列同源，用数据说话（我推理两次错过一级）
                    for (c1_k = 0; c1_k < 6; c1_k = c1_k + 1)
                        if (dsub((dut.x_d[c1_k] >> 1), dut.sx) != 0) c1_kbad[c1_k] = c1_kbad[c1_k] + 1;
                    // C1i（r63/#79）：换读口那次差点死在"相位接错一级"上（C1c 抓到 Δcol 24.8 %）。
                    //   这条把"读口的四个相位量必须与 `sx` 同一级标签同源"变成常设判据：
                    //   对**每一级**都数一遍 ⇒ 判据用的级数不是抄来的字面量，是同一份标定量出来的。
                    for (c1_k = 0; c1_k < 6; c1_k = c1_k + 1) begin
                        if (dut.u_bilin.col0     !== ~dut.x_d[c1_k][0]) c1_pbad[c1_k] = c1_pbad[c1_k] + 1;
                        if (dut.u_bilin.row0     !== ~dut.y_d[c1_k][0]) c1_pbad[c1_k] = c1_pbad[c1_k] + 1;
                        if (dut.u_bilin.pair_odd !==  dut.y_d[c1_k][1]) c1_pbad[c1_k] = c1_pbad[c1_k] + 1;
                        if (dut.u_bilin.req_vld  !==  dut.de_d[c1_k])   c1_pbad[c1_k] = c1_pbad[c1_k] + 1;
                    end
                    c1_gx  = dsub((dut.x_d[3] >> 1), dut.sx);   // 列：源列必须 = 同级的显示列 >>1
                    if (c1_gx != 0) begin
                        c1_geom_bad = c1_geom_bad + 1;
                        if (c1_gdump < 6) begin               // 前 10 处摆原始数：形状规则 = 尺子错
                            c1_gdump = c1_gdump + 1;
                            $display("[tb_v98_top_seam.v:424] GEOM x_d[3]=%0d 期望src=%0d 顶层src=%0d dx=%0d | de3=%0d oob=%0d sy=%0d y3=%0d",
                                     dut.x_d[3], (dut.x_d[3] >> 1), dut.sx, c1_gx,
                                     dut.de_d[3], dut.oob, dut.sy, dut.y_d[3]);
                        end
                    end
                    // 行：地址带着 #54 (B) 的提前量，所以期望是 (y + OFF_LINES) >> 1，不是 y >> 1。
                    //   提前量取顶层自己声明的 u_pipe.OFF_LINES（台架里独立算，不抄内部信号）。
                    // r63/#52 追加的第二项 `12'd2` 是**双线性读口的行方向代价补偿**（顶层 `BILIN_ROWS`）：
                    //   乒乓缓冲让"显示在第 Y 行的内容"来自上一对请求 ⇒ 请求行必须提前 2 个显示行，
                    //   否则整幅画面会在垂直方向错一行。这条与 `MIX_D` 无关（列方向仍是 2 拍）。
                    //   ⚠ 顶层哪天改了 BILIN_ROWS，这里必须同步改 —— 两处都是"设计上的提前量"，
                    //   不是判据松紧。为什么不用字面量算进去再判：那样 C1h 就退化成"期望 = 实测"。
                    // #97 第四笔 / #98：帧底没有行可提前 ⇒ 请求行是**绕回**的，不是夹到 299。
                    //   期望式子必须带上这一项 —— 不带的话这条判据把修好的那几行当成几何错位
                    //   （10:41 实测：红 1852 格、全在 y_d[2]>=596，而同一轮 C5c 正往相反方向红）。
                    // ⚠ 这一把尺子**跟着设计的定义走**（它就是"mapper 有没有发出这一行的定义行号"），
                    //   所以 #98 这一笔的凭据**不是它**，而是 C5c（面板级、期望只含 `屏上行>>1`、
                    //   不含绕回式的任何一项）。把它写在这里是因为上一轮就差点拿 C1h 当凭据自证 ——
                    //   #78/#88 记过的同一族：例外/期望 keyed 在被验对象上，就永远测不出漏。
                    c1_adv = (dut.y_d[2] + {4'd0, dut.pipe_off_rows[3:0]} + 12'd2) >> 1;
                    c1_exp = (c1_adv >= 12'd300) ? (c1_adv - 12'd300) : c1_adv;   // 绕回 = 减一次 SRC_H
                    c1_gy  = dsub(c1_exp, dut.sy);
                    // 落在绕回窗里的格数（`req ≥ 300` ⇔ `y ≥ 600 − OFF − BILIN`）：地板用，没有它
                    // 上面那一条退化成"永远走 else"，绿得毫无意义。
                    if (c1_adv >= 12'd300) c1_wrapn = c1_wrapn + 1;
                    // 期望**恰好等于末行 299** 的格数：绕回之后 299 仍然是合法行（y_d[2]=592、593），
                    // 数出来是为了证明"这里没有第二个例外"——旧写法 `if (dut.sy >= 299) skip` 拿被验
                    // 对象当例外条件，那一族从此修不红（#78/#88）。
                    if (c1_exp == (12'd300 - 1)) c1_clamp = c1_clamp + 1;
                    if (c1_gy != 0) c1_geom_bad_row = c1_geom_bad_row + 1;
                end
                if (c1_dx == 0) c1_zero = c1_zero + 1;
                else            c1_colbad = c1_colbad + 1;
                if (c1_dy != 0) begin
                    c1_rowbad = c1_rowbad + 1;
                    // #54 第 5 条的仪器：Δrow ≠ 0 的**形状**是什么？按 Δrow 值与列位置分桶，
                    //   再留 6 个原始样本。"集中在行边界"与"散布在全行"是两种完全不同的病，
                    //   光有一个 3704 的总数改不动任何东西。
                    if (c1_dy >= -4 && c1_dy <= 3) c1_rdh[c1_dy + 4] = c1_rdh[c1_dy + 4] + 1;
                    else if (c1_dy > 3)  c1_rdh[8] = c1_rdh[8] + 1;
                    else                 c1_rdh[9] = c1_rdh[9] + 1;
                    c1_rdbk[c1_col / 32] = c1_rdbk[c1_col / 32] + 1;
                    if (c1_rdump < 6) begin
                        c1_rdump = c1_rdump + 1;
                        $display("ROWMIX col=%0d y11=%0d | screen=%h dec(%0d,%0d) exp(%0d,%0d) dcol=%0d drow=%0d sx=%0d sy=%0d off=%0d",
                                 c1_col, c1_row, tap_raw, mem_row(tap_raw), mem_col(tap_raw),
                                 (c1_row >> 1), (c1_col >> 1), c1_dx, c1_dy,
                                 dut.sx, dut.sy, dut.pipe_off_rows);
                    end
                end
                if (c1_fcol == -999) begin c1_fcol = c1_dx; c1_frow = c1_dy; end
                else if (c1_dx != c1_fcol || c1_dy != c1_frow) c1_varies = c1_varies + 1;
                if (c1_dumped < 3) begin
                    c1_dumped = c1_dumped + 1;
                    $display("[tb_v98_top_seam.v:444] DBG2 x_sel=%0d y11=%0d | 屏上=%04x 期望列=%03d 期望行=%03d Δcol=%0d Δrow=%0d",
                             c1_col, c1_row, tap_raw, c1_col[7:0], (c1_row >> 1), c1_dx, c1_dy);                end
            end
        end
    end

    // ============================ C2（#92 的尺子）============================
    // 用户看到的是"贴在屏幕左边缘的一条、内容属于画面自己边缘的那一线"，而且**宽度随缩放变**。
    // 现有的 C1c 对这件事**没有牙**：它明确跳过 `c1_col < 25`（行首那 24 列的*行*标签与内容不同行），
    // 而那正是症状所在的位置 —— 这也是 #88 当时留下的问号（"C1c 有没有牙"）。
    // 所以这一格换一条**不引用 DUT 的 oob** 的期望：TB 自己按定义算逆映射
    //     画面列 = x>>1（r59b 的 ×2 复制，与 C1c 同一件事）
    //     源列   = IW/2 + floor((画面列 − IW/2)·inv/256)     （向 −∞ 取整，与 tb_v96 的 exp_sx 同一式子）
    // 于是"这一列该是背景黑"由台架自己判：DUT 的 oob 若漏了，这里就会红 —— 拿 oob 当期望永远测不出漏。
    // 只在**行方向安全的中段**采样（界在下面 `C2_YLO/C2_YHI`，按最小那一档的画面纵向收紧），
    // 这样"该黑"只可能由**列**越界造成，不需要再复制一份带 OFF/BILIN 补偿的行算式（那会引入新错源）。
    // 缩放八档全扫（V8-8 的档号表在 zoom_ctrl 里，TB 这一份是**独立抄的期望**）：
    //   0.50x 那一档先量到"画面比几何往左偏一列"，这一轮要回答的是"偏移量随不随倍率走"：
    //   随 `inv` 变 ⇒ 取整/半格的问题；**恒为一列** ⇒ 整拍之差（答案已经量出来了：恒为一列，
    //   inv=512 与 inv=1023 两档都是 1 列 ⇒ 见 report/ISSUES.md #92 的"量出来了"段）。
    //   每一档采 2 帧，按档号分别记账 ⇒ 一次跑完能看出"偏移 = f(inv)"的形状。
    // 采样行的上下界：必须**严格落在最小那一档（0.25x）的画面里面**。0.25x 时画面纵向只有
    //   600*256/1023 ≈ 150 行，居中 ⇒ y∈[225,375]。原来取 [225,374] 正好压在它的上下边界上，
    //   于是"画面里有黑格"量的是**纵向边界**（那几行的源行越界 ⇒ 设计上就是黑的），
    //   与要量的横向问题无关（inv=1023 那档 blank=2356，而横向真正缺的只有 900 格 = 一列）。
    //   收紧到 [240,360]：四档缩小倍率下都严格在画面内，边界效应交给 C3 的行结算去数。
    localparam integer C2_YLO = 240, C2_YHI = 360;
    // 八档表（TB 自己抄的一份，与 zoom_ctrl 的 tbl 互为反例源）：Verilog-2001 没有数组字面量，
    //   所以写成函数而不是 `'{...}` —— 那个是 SystemVerilog，xvlog 在 -i2v 下不认。
    function [9:0] C2_TBL; input [3:0] i;
        begin
            case (i)
                4'd0: C2_TBL = 10'd1023;   4'd1: C2_TBL = 10'd776;
                4'd2: C2_TBL = 10'd512;    4'd3: C2_TBL = 10'd341;
                4'd4: C2_TBL = 10'd256;    4'd5: C2_TBL = 10'd192;
                4'd6: C2_TBL = 10'd171;    default: C2_TBL = 10'd128;
            endcase
        end
    endfunction
    reg        c2_on = 1'b0;
    reg  [3:0] c2_k  = 4'd0;             // 当前在采哪一档（0..7；四位是为了能数到 8 停下来）
    integer c2_viol [0:7], c2_nout [0:7], c2_nin [0:7], c2_inbad [0:7], c2_invbad [0:7];
    integer c2_geol [0:7], c2_geor [0:7], c2_measl [0:7], c2_measr [0:7];
    integer c2_leakl [0:7], c2_leakr [0:7], c2_blank [0:7], c2_rows [0:7];
    integer c2_e, c2_bdump = 0;
    // 坏格落在**哪几个列对**上：484 这种数只说"每行错一对"，说不清是哪一对，而"哪一对"才决定修法
    //（行尾 ⇒ 末列折回；行首 ⇒ 乒乓/首拍；中间 ⇒ 地址级）。所以逐列对记一位。
    reg [511:0] c2_ibv [0:7];
    integer c2_ib_np, c2_ib_f, c2_ib_l, c2_ib_q;
    // 坏格的**差值形状**：18:11 那一轮的教训是"全局 dump 配额被第一档吃光，后面几档一个字没留下"
    //（30 行全花在 code 4 上，code 5/6/7 只有总数没有形状）。所以差值按档累计，打印也只按档配额。
    integer c2_dm1 [0:7], c2_dp1 [0:7], c2_doth [0:7], c2_ibc [0:7], c2_dd;
    integer c2_tbc [0:7];      // C2TAIL：每档允许摆几行行尾（见下面那段注释）
    // ---- C7（#102 的尺子）：**同一批采样点上的"行"标签** ----
    // 为什么 C2 绿着而用户看得见左缘一条线：C2 只比 `mem_col(sel)`（列），C1d 比行但**明确跳过
    // 源列 < 25 的那一窗**，C6 只看屏上第 0 列的**列**标签 ⇒ "最左若干源列画的是哪一行"今天
    // **一个数都没有**。用户 09-27 的矩阵（2.0x 看不见 / 0.5–1.0x 存在且宽度随倍率走 / 只在左边 /
    // 内容与左侧对齐但"有些延迟"）里那句"延迟"说的就是**行**：一列被错行复用，看起来就像边缘
    // 有一条跟着画面走的细带。所以这一条把行标签补在**与 C2 完全相同的采样窗**上（同拍、同点、
    // 同一份逆映射表），两把尺子的差别只剩"比的是哪一半位"。
    // 期望行的来源**不引用顶层的任何补偿项**（`OFF`/`BILIN`/绕回一个都不进）：
    //   图像行 = (屏上行 >>1)，再按该档 inv 逆缩放。为什么敢这样定：C5b 已经在 1.00x 证明
    //   "屏上第 Y 行画的就是图像行 Y>>1"（那是面板级、只用引脚建的坐标系），
    //   而 inv=256 时下面的式子恰好退化成它自己 ⇒ 这一条不是抄 DUT，是把已判绿的那条定义
    //   沿用到另外七档。若它红了而形状显示"所有列同差一行"，那是**我的复合算错了一档**，
    //   不是硬件错 —— 所以差值按 ±1/±2 分桶打出来，一眼分得开（同一族教训：#68/#78/#92/#98）。
    integer c7_rbad [0:7], c7_rn [0:7], c7_rm1 [0:7], c7_rp1 [0:7], c7_rblk [0:7];
    integer c7_rdc [0:7];                            // 每档允许的原始样本数（全局配额会被第一档吃光）
    reg  [511:0] c7_rbv [0:7];                       // 坏格的"源列对"位图（哪几列被错行）
    integer c7_np, c7_f, c7_l, c7_q, c7_dr, c7_er;

    initial begin
        for (c2_e = 0; c2_e < 8; c2_e = c2_e + 1) begin
            c2_viol[c2_e]=0; c2_nout[c2_e]=0; c2_nin[c2_e]=0; c2_inbad[c2_e]=0;
            c2_invbad[c2_e]=0; c2_rows[c2_e]=0;
            c7_rbad[c2_e]=0; c7_rn[c2_e]=0; c7_rm1[c2_e]=0; c7_rp1[c2_e]=0; c7_rblk[c2_e]=0;
            c7_rdc[c2_e]=0;
            c7_rbv[c2_e]=512'd0;
            c2_geol[c2_e]=-1; c2_geor[c2_e]=-1; c2_measl[c2_e]=-1; c2_measr[c2_e]=-1;
            c2_leakl[c2_e]=-1; c2_leakr[c2_e]=-1; c2_blank[c2_e]=0;
            c2_ibv[c2_e]=512'd0;
            c2_dm1[c2_e]=0; c2_dp1[c2_e]=0; c2_doth[c2_e]=0; c2_ibc[c2_e]=0; c2_tbc[c2_e]=0;
        end
    end

    function integer c2_exp_col; input integer x; input integer vi;
        integer d, p;
        begin
            d = (x >> 1) - (512/2);
            p = d * vi;
            c2_exp_col = (((p >= 0) ? (p / 256) : -(((-p) + 255) / 256)) + (512/2));
        end
    endfunction

    // C7：同一套逆映射，作用在**行**上。中心与高度都取本 TB 自己的源几何（`SRC_H`），
    // 与 `zoom_mapper` 里那两条 `IMAGE_H/2` 是同一件事的两处写法（一个是设计、一个是台架的期望）。
    // 取整方向与 `c2_exp_col` 逐字符相同（向 −∞ 取整），这样"列与行是同一把尺子"这句话在代码上
    // 就是真的，不是注释里说的。inv=256 时它恰好退化成 `y>>1` —— 那正是 C5b 已经在面板上判绿的
    // 那一条定义 ⇒ 这一条不是抄 DUT，是把已判绿的定义沿用到另外七档。
    function integer c2_exp_row; input integer y; input integer vi;
        integer d, p;
        begin
            d = (y >> 1) - (SRC_H/2);
            p = d * vi;
            c2_exp_row = (((p >= 0) ? (p / 256) : -(((-p) + 255) / 256)) + (SRC_H/2));
        end
    endfunction

    always @(posedge dut.clk_pix) begin
        // ⚠ 采样必须**整束同一级**：第一版用 `mix_de`/`mix_y`（第 11 级）去配 `u_split.x_sel`
        //   （第 20 级），于是每行开头 9 拍采到上一行的消隐尾（"首列 x=1335" 就是这么来的），
        //   结果 "该黑不黑" 报了 460800/460800 —— 红的是尺子，不是硬件（#68 同族，我重犯的）。
        if (c2_on && dut.de_d[dut.MIX_D] && dut.y_d[dut.MIX_D] >= C2_YLO
            && dut.y_d[dut.MIX_D] <= C2_YHI) begin
            c2_e = c2_exp_col(dut.u_split.x_sel, C2_TBL(c2_k));
            if (dut.inv_used !== C2_TBL(c2_k)) c2_invbad[c2_k] = c2_invbad[c2_k] + 1;
            if (c2_e < 0 || c2_e > 511) begin
                c2_nout[c2_k] = c2_nout[c2_k] + 1;
                if (dut.u_split.sel !== 16'h0000) begin
                    c2_viol[c2_k] = c2_viol[c2_k] + 1;
                    if (dut.u_split.x_sel < 512 && c2_leakl[c2_k] < 0) c2_leakl[c2_k] = dut.u_split.x_sel;
                    if (dut.u_split.x_sel >= 512) c2_leakr[c2_k] = dut.u_split.x_sel;
                end
            end else begin
                c2_nin[c2_k] = c2_nin[c2_k] + 1;
                // ---- C7：与上面**同一拍、同一个采样点**，只是比"行"那一半位（#102 缺的那把尺子）----
                c7_er = c2_exp_row(dut.y_d[dut.MIX_D], C2_TBL(c2_k));
                if (c7_er < 0 || c7_er > (SRC_H-1)) begin
                    // 这一档的画面纵向没铺到这条带 ⇒ 不参与行判定，但**必须数出来**：
                    // 少了这一位，"C7 全绿"就可能只是"样本集为空"（#78/#94 那一族的第三种死法）。
                    c7_rblk[c2_k] = c7_rblk[c2_k] + 1;
                end else begin
                    c7_rn[c2_k] = c7_rn[c2_k] + 1;
                    c7_dr = dsub(mem_row(dut.u_split.sel), c7_er[6:0]);   // 位图与 tag 都是 mod 128
                    if (c7_dr != 0) begin
                        c7_rbad[c2_k] = c7_rbad[c2_k] + 1;
                        c7_rbv[c2_k][dut.u_split.x_sel >> 1] = 1'b1;
                        if      (c7_dr == -1) c7_rm1[c2_k] = c7_rm1[c2_k] + 1;
                        else if (c7_dr ==  1) c7_rp1[c2_k] = c7_rp1[c2_k] + 1;
                        if (c7_rdc[c2_k] < 3) begin
                            c7_rdc[c2_k] = c7_rdc[c2_k] + 1;
                            // 摆"哪一路抽头错的"：orig 错 proc 对 ⇒ 原图那条环（#98 那一族）；
                            // 两路都错 ⇒ 错误在进链之前（mapper 的行号或读口的地址）。
                            $display("C7BAD code=%0d x=%0d y=%0d 解出行=%0d 期望行=%0d 差=%0d | sel=%h take_orig=%b orig=%h(r%0d) proc=%h(r%0d) oob=%b oob_out=%b sx=%0d sy=%0d",
                                     c2_k, dut.u_split.x_sel, dut.y_d[dut.MIX_D],
                                     mem_row(dut.u_split.sel), (c7_er & 8'h7F), c7_dr,
                                     dut.u_split.sel, dut.u_split.take_orig,
                                     dut.u_split.orig_pix, mem_row(dut.u_split.orig_pix),
                                     dut.u_split.proc_pix, mem_row(dut.u_split.proc_pix),
                                     dut.oob, dut.oob_out, dut.sx, dut.sy);
                        end
                    end
                end
                if (c2_geol[c2_k] < 0) c2_geol[c2_k] = dut.u_split.x_sel;
                c2_geor[c2_k] = dut.u_split.x_sel;
                if (dut.u_split.sel !== 16'h0000) begin
                    if (c2_measl[c2_k] < 0) c2_measl[c2_k] = dut.u_split.x_sel;
                    c2_measr[c2_k] = dut.u_split.x_sel;
                end else begin
                    c2_blank[c2_k] = c2_blank[c2_k] + 1;
                    // 诊断（不是判据）：画面里出现黑格时，把**这一拍两个抽头与 oob 标签**一起摆出来。
                    //   为什么必须摆原始的三样而不是继续推：改完 #92 那两笔之后，0.25x 那档还剩
                    //   "定义的最后一列是黑的"（blank = 242 = 一列 × 121 行 × 2 帧），而"是 oob 标签
                    //   在那儿翻了"还是"像素本身是 (0,0) 那格黑"这两种情形，在黑/非黑这一层**长得一样**，
                    //   推出来两次互相矛盾的模型（#68/#78 那一族每一轮都是"再推一遍"输的）。
                    if (c2_bdump < 6) begin
                        c2_bdump = c2_bdump + 1;
                        $display("C2BLK x_sel=%0d sx=%0d sy=%0d oob=%b oob_out=%b | orig=%h proc=%h sel=%h | inv=%0d bilin=%b jd=%0d",
                                 dut.u_split.x_sel, dut.sx, dut.sy, dut.oob, dut.oob_out,
                                 dut.u_split.orig_pix, dut.u_split.proc_pix, dut.u_split.sel,
                                 dut.inv_used, bilin_en_tb, dut.u_bilin.jd);
                    end
                end
                c2_dd = dsub(mem_col(dut.u_split.sel), c2_e);
                if (c2_dd != 0) begin
                    c2_inbad[c2_k] = c2_inbad[c2_k] + 1;
                    c2_ibv[c2_k][dut.u_split.x_sel >> 1] = 1'b1;
                    if      (c2_dd == -1) c2_dm1 [c2_k] = c2_dm1 [c2_k] + 1;
                    else if (c2_dd ==  1) c2_dp1 [c2_k] = c2_dp1 [c2_k] + 1;
                    else                  c2_doth[c2_k] = c2_doth[c2_k] + 1;
                    // 诊断（不是判据）：r70 那轮量到"1.00x/1.33x/1.5x 三档各 484 格对不上，
                    // 而 0.25x~0.75x 是 0、2.0x 也是 0" —— 484 = 2 列 × 121 行 × 2 帧 = **每行恰好一个列对**，
                    // 这种"只错一对"的形状必须知道它是**哪一对**才修得动（行首？行尾？中间？）。
                    // 只把数打出来不猜：#68/#78/#92 三轮的账都是"再推一遍"输的。
                    if (c2_ibc[c2_k] < 4) begin
                        c2_ibc[c2_k] = c2_ibc[c2_k] + 1;
                        // 摆**同一拍 mux 自己的两个抽头**，不摆 fb_bilin 的内部（那是另一级，
                        // 拿它配这一拍就是 #68/#92 反复交的税）。哪一路是错的，一眼就分得开：
                        //   orig 错 proc 对 ⇒ 原图那条延迟线（raw_line_delay/orig_skid）；
                        //   两路都错 ⇒ 错误在进链之前（mapper 坐标或 fb_bilin 的地址）。
                        $display("C2IBAD code=%0d x_sel=%0d pair=%0d 解出col=%0d 期望col=%0d 差=%0d | sel=%h take_orig=%b orig=%h(c%0d) proc=%h(c%0d) oob_out=%b y=%0d",
                                 c2_k, dut.u_split.x_sel, (dut.u_split.x_sel >> 1), mem_col(dut.u_split.sel),
                                 c2_e, c2_dd, dut.u_split.sel, dut.u_split.take_orig,
                                 dut.u_split.orig_pix, mem_col(dut.u_split.orig_pix),
                                 dut.u_split.proc_pix, mem_col(dut.u_split.proc_pix),
                                 dut.oob_out, dut.y_d[dut.MIX_D]);
                    end
                end
            end
            // ---- C2TAIL：把**行尾 6 列**在同一拍上摆开（诊断，不是判据；每档限 6 行）----
            // 为什么需要它：模块级与整链级（`tb_v89` 的 ID 判据）已经逐列恒等，可顶层每行最后一列对
            // 仍然少一格 ⇒ 病灶只可能在**顶层特有**的那几环：链子吃的标签级是 `de_d[3]/x_d[3]`
            // 而行环吃的是 `de_d[5]/x_d[5]`；链子输出又多寄存了一拍（`pipe_dout_q`，#92 第一笔）；
            // 混色级吃的标签是 `x_d[MIX_D]`。这三件事在行中间互相抵消、只在行尾露馅 ⇒
            // 必须同拍看到"读口给的什么、链子给的什么、混色级吃的什么、标签说什么"。
            // 教训（#68/#78/#92 每一轮都是"再推一遍"输的）：摆原始数，一眼就分得开。
            if (c2_tbc[c2_k] < 6 && dut.u_split.x_sel >= (2*512-6) && dut.u_split.x_sel <= (2*512-1)) begin
                c2_tbc[c2_k] = c2_tbc[c2_k] + 1;
                $display("C2TAIL code=%0d x=%0d exp=%0d | mix sel=%h(c%0d) orig=%h(c%0d) proc=%h(c%0d) | chain_out=%h(c%0d) chain_de=%b mix_de=%b | fb jd=%0d res=%h(c%0d) asm=%b | blur de=%b x=%0d owed=%b lend=%b",
                         c2_k, dut.u_split.x_sel, c2_exp_col(dut.u_split.x_sel, C2_TBL(c2_k)),
                         dut.u_split.sel, mem_col(dut.u_split.sel),
                         dut.u_split.orig_pix, mem_col(dut.u_split.orig_pix),
                         dut.u_split.proc_pix, mem_col(dut.u_split.proc_pix),
                         dut.pipe_dout, mem_col(dut.pipe_dout), dut.pipe_de,
                         dut.de_d[dut.MIX_D], dut.u_bilin.jd, dut.u_bilin.res_q[15:0],
                         mem_col(dut.u_bilin.res_q[15:0]), dut.u_bilin.asm_d2,
                         dut.u_pipe.u_blur.de_in, dut.u_pipe.u_blur.x_in,
                         dut.u_pipe.u_blur.owed, dut.u_pipe.u_blur.line_end === 1'b1);
            end
        end
    end

    // ============================ C3（#92 的第二把尺子：面板级）============================
    // C2 采的是 `de_d[MIX_D] + x_sel + u_split.sel` —— **全部在内容那一级**，所以它量的是
    // "内容 vs 内容自己的标签"。而用户看的是**屏上**：面板只认 `de_osd/vs_osd/r_osd/g_osd/b_osd`
    // 这五根线，它把"de 为高的第几拍"当成第几列。这两套坐标系之间如果差 N 拍，屏上就整体偏 N 列，
    // 而 C2 一个数都看不见 —— #92 用户报的"屏幕左边缘一条从视频里切出来的线"正是这一族。
    // 顺带说清一件让人不舒服的事：C1c 的注释里那句"行首尾各 24 列里第 11 级的行标签已经跳到
    // 下一行而内容还在本行"**就是这个 9 列之差的现场**，当时把它当成台架的不便跳过去了，
    // 没有当成硬件的账（#68 那一族的第三回：标签与内容不同级）。
    // 所以这一格**只用输出引脚**建坐标系：面板列号 = 本行 de 为高的第几拍，面板行号 = vs 上升沿
    // 之后第几个 de 跑。判据不引用任何内部标签 ⇒ "画面在屏上偏了几列"第一次有了机器数。
    // 两条必须一起说的限制：
    //   ① 只数 `p_row >= C3_ROW0` 的行：OSD 那个框在 y∈[12, 12+5*31)，会把自己涂成非黑；
    //   ② 采这段时间把那条 2 px 标记线**关掉**（gp[13]=1 = `split marker 0`）：
    //      缝位钉在 0 时 `x_sel==seam` 恰好在屏上第几列画两格蓝，不关掉就是在量台架自己。
    // ============================ C4（#93 的第一把尺子：旋转下的"形状"）============================
    // 为什么按形状判而不按坐标判：要在台架里复算 `zoom_mapper` 的逆映射（sin/cos 的 Q 格式、
    // 中心取整、越界钉 0）就等于把被测的那段代码再抄一遍——抄错也一起错（#88 那一课）。
    // 而用户那三句话本身是**形状**陈述："右上方一道宽彩条，内容和右下角一样"、"屏幕左边一条细线，
    // 画的是旋转前的内容" ⇒ 这两件事都有一个不依赖坐标的签名：
    //   **一条旋转后的矩形画面，被任何一条水平线切到的部分只能是**一段**连续区间。**
    // 于是"某一行的非黑段数 > 1"就是那两道多出来的东西，而"段数 <= 1"不需要知道画面在哪。
    // 黑 = 画面外：这个等价关系由 C0a3 先证明（图卡 300×512 个格子里没有一格编码成全黑），
    // 再把那条 2 px 缝标记关掉、并把 OSD 那个框所在的行排除掉（C3_ROW0 以下才采）。
    // ⚠ 这一段走最近邻（bilin off）：插值会把两格的 tag 混成第三格，那时"非黑"仍然成立但
    //   "这一格是哪一格"不再成立 —— 形状判据不需要它，就别把它拉进来。
    //
    // ---------- 第二轮（2026-09-27）：为什么必须加"倍率"这一维，光有角度是不够的 ----------
    // 1.00x 那四条（0/45/90/168）**全绿**（`多段行=0`，四档各 780 行有画面），90° 量的
    // 第1列/末列 = [212..212]/[811..811] 正好是几何该给的那 600 列 ⇒ 尺子会分辨形状（它不是
    // 一条恒真的线），但**它在这一维上根本看不见 #93**：
    //   1.00x 时画面铺满整屏 ⇒ 屏上没有一列背景 ⇒ 任何多出来的东西（左缘那条细线、右上角
    //   那道宽彩条）都**贴在**同一个非黑段上，段数还是 1。"每行一段"在这个倍率下是结构上
    //   必然成立的，红不了 —— 这正是"绿着不等于验过"（#60 那一课的几何版）。
    // 0.50x 时画面只占 x∈[256,767]，两侧各 256 列背景 ⇒ 多出来的东西第一次有了可以站身的
    // 地方，"段数=2"才可能真的出现。所以第二维取 `zoom_sel=2`（inv=512=0.50x，见 C2_TBL），
    // 而不是 0.75x/1.00x 那些"没有背景带"的档 —— 用户原话是"只要缩放到非 100% 那条线就在"。
    // 判据不变（还是 C4b 数段数），只是把同一把尺子架到它**看得见病**的那一格上。
    // 第三档再加 0.25x（inv=1023，背景带各 384 列）：ISSUES #93 (C) 段写的就是这个矩阵
    //   `angle ∈ {0,45,90,168} × inv ∈ {1023,512,256}`，一次跑齐，别留给"下次再说"。
    localparam integer C4_NA   = 12;                   // 4 个角度 × 3 个倍率（0..3=1.00x，4..7=0.50x，8..11=0.25x）
    reg        c4_on = 1'b0;
    // ⚠ 扫描下标用 `integer` 而不是定宽 reg，是被两回坑之后定的：
    //   · 定宽 [1:0] 配 `c4_a < 4`：数到 3 回卷成 0 ⇒ for 永不退出，xsim 安静跑到超时，
    //     看起来像"台架卡死"（其实是循环变量装不下上界）；
    //   · 定宽 [2:0] 配 `c4_a < 3'd8`：Verilog 的比较是**自定宽**的，那个 8 先被截成 0 ⇒
    //     条件恒假 ⇒ 整个 C4 一档都不跑，而台架**全绿**（八档一个样本都没采）。
    //   `integer` 两头都不怕，而它只是台架里的循环变量，不进硬件。
    integer  c4_a  = 0;
    // ⚠ Verilog-2001 的数组声明要的是**范围**（`[0:N-1]`），`[N]` 是 SystemVerilog 写法：
    //   xvlog 在 -i2v 下报 "single value range is not allowed"，整个台架模块被忽略（#88 那一族的另一张脸）。
    integer    c4_rows2[0:C4_NA-1], c4_zero[0:C4_NA-1], c4_bad[0:C4_NA-1];
    integer    c4_fmin[0:C4_NA-1], c4_fmax[0:C4_NA-1], c4_lmin[0:C4_NA-1], c4_lmax[0:C4_NA-1];
    integer    c4_run, c4_r1s, c4_r1e, c4_r2s, c4_dump = 0;   // c4_dump 是**跨档累计**的上限，见下面 16
    reg        c4_prev_nb = 1'b0, c4_nb;
    integer    c4_e;

    initial begin
        for (c4_e = 0; c4_e < C4_NA; c4_e = c4_e + 1) begin
            c4_rows2[c4_e]=0; c4_zero[c4_e]=0; c4_bad[c4_e]=0;
            c4_fmin[c4_e]=-1; c4_fmax[c4_e]=-1; c4_lmin[c4_e]=-1; c4_lmax[c4_e]=-1;
        end
    end

    localparam integer C3_ROW0 = 210;              // 离开 OSD 那个框（含 vs 沿约定的余量）
    reg        c3_vs_d = 1'b0, c3_de_d = 1'b0;
    integer    c3_prow = 0, c3_pcol = 0, c3_pw = 0, c3_first = -1, c3_last = -1;
    integer    c3_rows [0:7], c3_empty [0:7], c3_fmin [0:7], c3_fmax [0:7];
    integer    c3_lmin [0:7], c3_lmax [0:7], c3_wbad [0:7], c3_rbad [0:7];
    integer    c3_devdump = 0;
    integer    c3_e;

    initial begin
        for (c3_e = 0; c3_e < 8; c3_e = c3_e + 1) begin
            c3_rows[c3_e]=0; c3_empty[c3_e]=0; c3_wbad[c3_e]=0; c3_rbad[c3_e]=0;
            c3_fmin[c3_e]=-1; c3_fmax[c3_e]=-1; c3_lmin[c3_e]=-1; c3_lmax[c3_e]=-1;
        end
    end

    always @(posedge dut.clk_pix) begin
        // 块内一律**阻塞赋值**：这几个 reg 只有本块写，读到的就是"上一拍的值"，
        // 与 DUT 的非阻塞更新在同一个沿上不抢先后（读 DUT 的寄存器输出同理：非阻塞更新
        // 发生在 NBA 区，本块在 active 区读到的必是本拍之前的值 ⇒ 五根线天然同拍）。
        // ⚠ 记账**每拍都在跑**，只有"结算进哪一档"才看 `c2_on`：第一版把整段包在 `if (c2_on)`
        //   里，于是 `c3_prow` 只在采样那两帧里涨，第一次 vs 上升沿读到一个"半帧"的行数 ⇒
        //   `c3_rbad` 每档白红一次。面板的行数是**整帧**才数得清的东西，不能跟着采样窗开停。
        if (dut.vs_osd && !c3_vs_d) begin            // 帧首：面板行号归零
            if (c2_on && c3_prow !== 600)            // 一帧必须正好 600 个 de 跑
                c3_rbad[c2_k] = c3_rbad[c2_k] + 1;
            c3_prow = 0;
        end
        c3_vs_d = dut.vs_osd;
        if (dut.de_osd && !c3_de_d) begin            // 行首
            c3_pcol = 0; c3_pw = 0; c3_first = -1; c3_last = -1;
            c4_run = 0; c4_prev_nb = 1'b0; c4_r1s = -1; c4_r1e = -1; c4_r2s = -1;
        end else if (dut.de_osd) c3_pcol = c3_pcol + 1;
        if (dut.de_osd) begin
            c3_pw = c3_pw + 1;
            if ({dut.r_osd, dut.g_osd, dut.b_osd} !== 24'd0) begin
                if (c3_first < 0) c3_first = c3_pcol;
                c3_last = c3_pcol;
            end
            // C4：同一拍顺手数"这一行的非黑段有几段"（与上面那三行用的是同一束线，不分二级）
            c4_nb = ({dut.r_osd, dut.g_osd, dut.b_osd} !== 24'd0);
            if (c4_nb && !c4_prev_nb) begin
                c4_run = c4_run + 1;
                if (c4_run == 1) c4_r1s = c3_pcol;
                if (c4_run == 2) c4_r2s = c3_pcol;
            end
            if (c4_nb && c4_run == 1) c4_r1e = c3_pcol;
            c4_prev_nb = c4_nb;
        end
        if (!dut.de_osd && c3_de_d) begin            // 行尾：结算这一行
            if (c2_on) begin
                if (c3_pw !== 1024) c3_wbad[c2_k] = c3_wbad[c2_k] + 1;  // 有效窗口必须正好 1024 列
                if (c3_prow >= C3_ROW0) begin
                    if (c3_first < 0) c3_empty[c2_k] = c3_empty[c2_k] + 1;   // 画面没铺到这一行
                    else begin
                        c3_rows[c2_k] = c3_rows[c2_k] + 1;
                        if (c3_fmin[c2_k] < 0) begin
                            c3_fmin[c2_k] = c3_first; c3_fmax[c2_k] = c3_first;
                            c3_lmin[c2_k] = c3_last;  c3_lmax[c2_k] = c3_last;
                        end else begin
                            // 偏离档内众数边界的行**当场摆出来**（前 6 行）：0.50x/0.75x 两档量到
                            // "某些行的左沿晚两列 = 晚一个源列"，而同一档的内容级三条（inbad/viol/blank）
                            // 全是 0 ⇒ 这不是几何平移，是"某些行的第一格恰好是黑的"。黑有两种：
                            // 越界回黑（那是 bug）与图卡自己的 (0,0)/(256,0) 那格（那是图案）。
                            // 光靠黑/非黑分不开这两者，所以把这一行的行标签 `y_d[MIX_D]` 一起打出来：
                            // 台架自己按定义算一次源行，就知道是不是图案的黑格（#92：先量，别猜）。
                            if ((c3_first != c3_fmin[c2_k] || c3_last != c3_lmax[c2_k]) && c3_devdump < 6) begin
                                c3_devdump = c3_devdump + 1;
                                $display("C3DEV code=%0d prow=%0d first=%0d last=%0d |档内 first[%0d..%0d] last[%0d..%0d] y_d[MIX_D]=%0d geol=%0d geor=%0d",
                                         c2_k, c3_prow, c3_first, c3_last,
                                         c3_fmin[c2_k], c3_fmax[c2_k], c3_lmin[c2_k], c3_lmax[c2_k],
                                         dut.y_d[dut.MIX_D], c2_geol[c2_k], c2_geor[c2_k]);
                            end
                            if (c3_first < c3_fmin[c2_k]) c3_fmin[c2_k] = c3_first;
                            if (c3_first > c3_fmax[c2_k]) c3_fmax[c2_k] = c3_first;
                            if (c3_last  < c3_lmin[c2_k]) c3_lmin[c2_k] = c3_last;
                            if (c3_last  > c3_lmax[c2_k]) c3_lmax[c2_k] = c3_last;
                        end
                    end
                end
            end
            if (c4_on && c3_prow >= C3_ROW0) begin
                if (c4_run == 0) c4_zero[c4_a] = c4_zero[c4_a] + 1;      // 这一行没画面（0.50x 与大角度下都正常）
                else if (c4_run == 1) begin
                    c4_rows2[c4_a] = c4_rows2[c4_a] + 1;
                    if (c4_fmin[c4_a] < 0) begin
                        c4_fmin[c4_a] = c4_r1s; c4_fmax[c4_a] = c4_r1s;
                        c4_lmin[c4_a] = c4_r1e; c4_lmax[c4_a] = c4_r1e;
                    end else begin
                        if (c4_r1s < c4_fmin[c4_a]) c4_fmin[c4_a] = c4_r1s;
                        if (c4_r1s > c4_fmax[c4_a]) c4_fmax[c4_a] = c4_r1s;
                        if (c4_r1e < c4_lmin[c4_a]) c4_lmin[c4_a] = c4_r1e;
                        if (c4_r1e > c4_lmax[c4_a]) c4_lmax[c4_a] = c4_r1e;
                    end
                end else begin                                              // 两段以上 = #93 那两道多出来的东西
                    c4_bad[c4_a] = c4_bad[c4_a] + 1;
                    // 上限 16 而不是 8：现在有八档，前四档（1.00x）注定一段都没有，
                    // 全部配额该留给真正可能看见病的后四档；这个计数器只由本块写，所以
                    // 不在激励里按档清零（两个进程写同一根激励位 = #94 那一族的错）。
                    if (c4_dump < 16) begin
                        c4_dump = c4_dump + 1;
                        $display("C4RUN ang=%0d zoomsel=%0d prow=%0d 段数=%0d 第1段=[%0d,%0d] 第2段从=%0d 末段到=%0d | y_d[MIX_D]=%0d sx=%0d sy=%0d oob_out=%b",
                                 c4_ang_of(c4_a), c4_pct_of(c4_a), zoom_sel, c3_prow, c4_run, c4_r1s, c4_r1e, c4_r2s, c3_last,
                                 dut.y_d[dut.MIX_D], dut.sx, dut.sy, dut.oob_out);
                    end
                end
            end
            c3_prow = c3_prow + 1;
        end
        c3_de_d = dut.de_osd;
    end

    // ============================ C5（#97 追加二：行维那把缺的尺子）============================
    // C2/C3/C4 判的都是**列**与**段数**：顶边那一条带画的是"这张图自己的最后一行"，
    // 它不改变左右沿、不改变段数 ⇒ 三把尺子一起绿，而屏上有东西。C5 判"这一格画的是哪一源行"：
    // 图卡把 (源行, 源列) 写进像素 tag（`px_val`），逐行解 tag 就能把行内容钉成数。
    // 取点在 `split_display` 的输出（r/g/b + de_o/vs_o），**不是 OSD 之后**：
    // OSD 那个框盖住屏上最上面一百来行，取在它后面等于什么都没看（而这一条要看的恰恰是那几行）。
    // 只在 `angle=0 × 1.00x`（C4 的第 0 格）判：那一档"源行 = 显示行 / 2"是定义，别档不是。
    localparam integer C5_COL = 512;                 // 圈内、离两沿都远的一列
    // #97 追加七（10:5x）：**一列不够**。混色级是"缝左原图 / 缝右处理图"，而两路各自的帧头滞后
    //   是**两件不同的事**（原图那路 = `raw_line_delay` 的槽，处理那路 = 链子的行缓存），
    //   只采一列等于只看一面 —— 上一轮 C1d-b 那一条"帧头正名"就是死在没有样本上（c1_ring 实测 0，
    //   行标签与内容在行首不同行 ⇒ 那几格从来落不进 C1 的采样窗）。现在三列一起采，
    //   哪一列红就是哪一路的红（DIAG 打的是屏上列号）。
    localparam integer C5_LA = 300, C5_RA = 900;     // 缝的左右两侧各取一列（缝在中间那一档）
    integer c5_prow = 0, c5_pcol = 0, c5_vs_d = 0, c5_de_d = 0;
    integer c5_bad = 0, c5_judged = 0, c5_head = 0, c5_head_bad = 0, c5_dump = 0;
    integer c6_n = 0, c6_bad = 0, c6_dump = 0;         // C6：屏上每行第 0 格的**源列**（1.00x 下没有背景可比）
    integer j5 = 0;                                    // 本拍采到的那一列是第几列（0=左 1=中 2=右）
    integer c5_head_c [0:2];                           // 各列的"帧头窗"可判格数（覆盖地板）
    integer c5_headbad_c [0:2];                        // 各列帧头窗里内容不符的格数
    integer c5_jud_c [0:2], c5_badc_c [0:2];           // 各列本体的可判/不符格数
    integer c5_off;
    reg [15:0] c5_px;
    reg [7:0] c5_got, c5_exp;
    wire c5_on = c4_on && (c4_a == 0);               // C4 第 0 格 = 不旋转 × 100 %

    always @(posedge dut.clk_pix) begin
        if (dut.vs_o && !c5_vs_d) c5_prow = 0;
        c5_vs_d = dut.vs_o;
        if (dut.de_o && !c5_de_d) c5_pcol = 0;
        else if (dut.de_o) c5_pcol = c5_pcol + 1;
        if (dut.de_o && c5_on && (c5_pcol == 0 || c5_pcol == C5_LA || c5_pcol == C5_COL || c5_pcol == C5_RA)) begin
            c5_px  = {dut.r[7:3], dut.g[7:2], dut.b[7:3]};   // 888 → 565 复原（展开是位复制，无损）
            c5_got = mem_row(c5_px);                          // tag 里的源行是 mod 128
            c5_exp = ((c5_prow >> 1) & 8'h7F);
            j5 = (c5_pcol == C5_LA) ? 0 : (c5_pcol == C5_COL) ? 1 : 2;
            if (c5_pcol == 0) begin
                // C6：**屏上每一行的第 0 格**不许是上一行末尾那一格。
                // `raw_line_delay` 是 (4 行 + 1 拍) 的环 ⇒ 原图抽头天生比标签晚一格，
                // 而 #92 第三笔把 oob 与像素**打包过环**，所以"背景档"下第 0 格是黑的（C2 看得见）。
                // 但在 `1.00x`（画面铺满、没有背景）这一格没有任何尺子判过：
                // 若那一格真的是上一行的末列，用户看到的就是"左边缘一条从视频里切出来的线"，
                // 而 C2/C4 全都只会绿（没有背景带可以比）。tag 里有源列 ⇒ 直接判。
                c6_n = c6_n + 1;
                if (mem_col(c5_px) !== 8'd0) begin
                    c6_bad = c6_bad + 1;
                    if (c6_dump < 6) begin
                        c6_dump = c6_dump + 1;
                        $display("C6HEAD prow=%0d px=%h 源列tag=%0d 期望=0 | 源行tag=%0d",
                                 c5_prow, c5_px, mem_col(c5_px), c5_got);
                    end
                end
            end else if (c5_prow < (c5_off + 2)) begin  // 帧头那一窗：OFF_LINES 行 + 读口成对滞后的 2 行
                c5_head = c5_head + 1;
                c5_head_c[j5] = c5_head_c[j5] + 1;
                if (dsub(c5_got, c5_exp) != 0) begin
                    c5_head_bad = c5_head_bad + 1;
                    c5_headbad_c[j5] = c5_headbad_c[j5] + 1;
                end
                if (c5_dump < 18) begin        // 3 列 × 帧头窗 6 行（`OFF+2`）：只放 4 行就看不见 4/5 行
                    c5_dump = c5_dump + 1;
                    $display("C5HEAD col=%0d prow=%0d px=%h 源行tag=%0d 定义=%0d | 屏上这一格来自哪一行的判决",
                             c5_pcol, c5_prow, c5_px, c5_got, c5_exp);
                end
            end else begin
                c5_judged = c5_judged + 1;
                c5_jud_c[j5] = c5_jud_c[j5] + 1;
                if (dsub(c5_got, c5_exp) != 0) begin
                    c5_bad = c5_bad + 1;
                    c5_badc_c[j5] = c5_badc_c[j5] + 1;
                end
            end
        end
        // 行号必须在**行尾**加一：少了这一句，`c5_prow` 永远停在 0 ⇒ 每一格都被当成"帧头那几行"，
        // C5a 的 judged 会是 0（覆盖地板正确地红）、C5c 把整帧都算成陈旧行 —— 第一跑就是这么红的，
        // 红的是尺子，不是被测对象（本仓第四次撞到同一族，见 ISSUES #94 的"台架相位"那条）。
        if (!dut.de_o && c5_de_d) c5_prow = c5_prow + 1;
        c5_de_d = dut.de_o;
    end

    // ---- C8（#102 的判据：**每一行的第一格**，两个抽头各自判）----
    //   为什么必须有它，而 C5/C6/C7 都不够：C5/C7 采样列在 300/512/900，**从来不判第 0 列**；
    //   C6 判第 0 列但只看"屏上那一格"，而屏上是缝选中的那一路（今天 = 处理抽头），
    //   且它只比**列**不比行。P100 量到的两条病灶恰好都躲在第 0 列：
    //     · 原图抽头的第 0 列摆的是"源列 160"（= 消隐期地址读回来的格子）⇒ 用户念的左缘细线；
    //     · 处理抽头的第 0 列在帧头那几行摆的是别的行（这一条归 C5c 判，不在 C8 的窗里）。
    //   所以 C8 把窗限定在**本体行**（`y ≥ OFF+BILIN`），只问一件事：第 0 列是不是本行的第一列。
    //   两路分开数、分开判 ⇒ 红了直接说出是哪一路（不再需要跑板子上做 `split` A/B）。
    integer c8_os = 0, c8_ob = 0, c8_ps = 0, c8_pb = 0, c8_odump = 0, c8_pdump = 0;
    always @(posedge dut.clk_pix) begin
        if (c5_on && dut.u_split.de && dut.u_split.x == 12'd0
            && dut.u_split.y >= (c5_off + 2) && dut.u_split.y < 12'd595) begin
            // 期望：源列 = 0，源行 = 面板行 >>1（`px_val` 的 tag 是 mod 128/256，用 dsub 判小偏移）
            c8_os = c8_os + 1;
            if (mem_col(dut.u_split.orig_pix) !== 8'd0
                || dsub(mem_row(dut.u_split.orig_pix), ((dut.u_split.y >> 1) & 8'h7F)) != 0) begin
                c8_ob = c8_ob + 1;
                if (c8_odump < 6) begin
                    c8_odump = c8_odump + 1;
                    $display("C8OBAD y=%0d 原图第0列=(行%0d,列%0d) 定义=(行%0d,列0) oob=%b",
                             dut.u_split.y, mem_row(dut.u_split.orig_pix), mem_col(dut.u_split.orig_pix),
                             (dut.u_split.y >> 1) & 8'h7F, dut.u_split.oob);
                end
            end
            c8_ps = c8_ps + 1;
            if (mem_col(dut.u_split.proc_pix) !== 8'd0
                || dsub(mem_row(dut.u_split.proc_pix), ((dut.u_split.y >> 1) & 8'h7F)) != 0) begin
                c8_pb = c8_pb + 1;
                if (c8_pdump < 6) begin
                    c8_pdump = c8_pdump + 1;
                    $display("C8PBAD y=%0d 处理第0列=(行%0d,列%0d) 定义=(行%0d,列0) oob=%b",
                             dut.u_split.y, mem_row(dut.u_split.proc_pix), mem_col(dut.u_split.proc_pix),
                             (dut.u_split.y >> 1) & 8'h7F, dut.u_split.oob);
                end
            end
        end
    end

    // `OFF_LINES` 从**被测对象**取，不抄字面量（#68 那条老规矩：抄来的数会变成"我相信我自己"）。
    initial c5_off = dut.u_pipe.OFF_LINES;

    // ================= P100（#98/#102 的探针：**面板级、两个抽头一起量**，只打印不判定）=================
    // 为什么已有的 C5/C6/C7 三个都不够：它们判的是**引脚上那一格**，而引脚上是谁由缝位决定 ——
    //   台架把 `split_ctl_tb` 钉在 0 ⇒ `left=(x_sel<0)=0` ⇒ `take_orig=~left... ` 见 split_display，
    //   实测结果是**整屏都是处理抽头**。而用户念的两条症状（屏顶带、左缘细线）在 r79 那次
    //   用 `split 0` / `split 100` 的屏上 A/B 已经钉在**原图抽头**上 ⇒ 顶层台架对被判的那一路
    //   是**全盲**的（P98 量的是链路中间的 `raw_ring`，不是屏上那一格）。
    // 这一段的办法不是去动缝位（那会把 C2/C3/C4/C5/C6/C7 的既有数全改一遍、凭据作废重来），
    //   而是直接取 `u_split` 的两个**输入**：`orig_pix` / `proc_pix` 与混色级同一拍、同一格，
    //   缝选谁都在它旁边 —— 于是一次跑就把两路各自的 (源行, 源列) 摆出来，不必猜。
    // ⚠ 这一跑仍然在 `c5_on` 的窗里（0° × 1.00x × 最近邻、标记线关）：与 C5/C6 同一激励，
    //   两边的数才能对着读。行数只取**帧头 10 行 + 帧尾 5 行 + 中间一行**，列只取**左右各 3 列**
    //   ⇒ 一帧 90 条、上限 200 条，不会把日志淹掉（P98 的教训：探针要能被读完）。
    // ⚠ **采样必须落在混色级自己的标签上，不能落在引脚上**：`split_display` 的输出是打拍的，
    //   引脚 `de_o` 拉高的那一拍，`sel` 已经是**上一拍**的内容 ⇒ 第一版这里自发把两路都读成
    //   "列 = (pcol+1)>>1"，看着像两个抽头都偏一列，其实是探针自己晚了一拍（#92 同族，第 N 次）。
    //   所以这一段的窗用 `u_split.de`、坐标用 `u_split.x/y`（= 顶层的 `x_d[MIX_D]/y_d[MIX_D]`），
    //   与它同一拍的 `orig_pix/proc_pix` 才是同一格。期望按定义当场算在打印里，读的人不用推。
    integer p100_n = 0;
    always @(posedge dut.clk_pix) begin
        if (c5_on && dut.u_split.de && p100_n < 200 &&
            (dut.u_split.y < 10 || dut.u_split.y == 12'd300 || dut.u_split.y >= 12'd595) &&
            (dut.u_split.x < 12'd3  || dut.u_split.x > 12'd1020)) begin
            p100_n = p100_n + 1;
            $display("PROBE P100 x=%0d y=%0d 定义(行%0d,列%0d) | 原图(行%0d,列%0d) 处理(行%0d,列%0d) | oob=%b take_orig=%b sel=%h",
                     dut.u_split.x, dut.u_split.y, (dut.u_split.y >> 1) & 8'h7F, (dut.u_split.x >> 1) & 8'hFF,
                     mem_row(dut.u_split.orig_pix), mem_col(dut.u_split.orig_pix),
                     mem_row(dut.u_split.proc_pix),  mem_col(dut.u_split.proc_pix),
                     dut.u_split.oob, dut.u_split.take_orig, dut.u_split.sel);
        end
    end

    // ================= P98（#98 的探针：**只打印，不判定**）=================
    // 为什么要它：C5c 量到"帧头 0..3 行的内容是源行 1"，而按 C1h（mapper 第 3 级的 sy 逐格对过）
    //   + C1d（环出口 = 标签行 >>1）推，帧头该读到的是**尾行 596..599 写进 4..7 号槽**的内容，
    //   而那两个式子谁也没说"环的写入口那一拍摆着哪一源行" —— 中间隔着 fb_bilin 的乒乓。
    //   再推第三种模型没有意义，直接把**写侧每一尾行的 tag**与**读侧每一头行的 tag**打成表：
    //   一次跑完就知道差的是"写进去的东西"还是"槽的对齐"。
    //   每行只在 `x_d[5]==0` 那一拍打一条 ⇒ 10 条尾行 + 8 条头行，不把日志淹掉。
    integer p98_w = 0, p98_r = 0, p98_m = 0;
    always @(posedge dut.clk_pix) begin
        if (c5_on && dut.de_d[5] && dut.x_d[5] == 12'd0) begin
            if (dut.y_d[5] >= 12'd588 && p98_w < 12) begin
                p98_w = p98_w + 1;
                $display("P98W 写侧 y_d5=%0d 槽=%0d | pix_raw tag=(行%0d,列%0d) oob=%b | sy=%0d y_d2=%0d",
                         dut.y_d[5], dut.y_d[5][2:0], mem_row(dut.pix_raw), mem_col(dut.pix_raw),
                         dut.oob_fb_d1, dut.sy, dut.y_d[2]);
            end
            if (dut.y_d[5] < 12'd8 && p98_r < 8) begin
                p98_r = p98_r + 1;
                $display("P98R 读侧 y_d5=%0d 读槽=%0d | 环出口 tag=(行%0d,列%0d) | 写入口同拍 tag=行%0d",
                         dut.y_d[5], dut.y_d[5][2:0] - 3'd4,
                         mem_row(dut.raw_ring[15:0]), mem_col(dut.raw_ring[15:0]),
                         mem_row(dut.pix_raw));
            end
            // P98M（r80 那一轮补的"帧中间对照"）：头尾两段的数都有了，但**没有一个数说"帧中间
            //   地址说要哪一行、环里走的又是哪一行"** ⇒ 头那几行的偏差没法归一（是"读口滞后"还是
            //   "绕回窗早了/晚了两行"，只有拿中间的常数当零点才分得开）。同一拍的地址三件
            //   （`y_req_row` 请求行 / `cy_r` 折回本帧的行号）与两路的 tag 一起打，中间段的
            //   "环出口 − 定义"就是这一把尺子的零点，头/尾的数才读得懂。
            if (dut.y_d[5] >= 12'd300 && dut.y_d[5] < 12'd304 && p98_m < 8) begin
                p98_m = p98_m + 1;
                $display("PROBE P98M y_d5=%0d 定义行=%0d | 请求 y_req_row=%0d cy_r=%0d | 环入口 tag=(行%0d,列%0d) 环出口 tag=(行%0d,列%0d)",
                         dut.y_d[5], (dut.y_d[5] >> 1) & 8'h7F, dut.y_req_row, dut.cy_r,
                         mem_row(dut.pix_raw), mem_col(dut.pix_raw),
                         mem_row(dut.raw_ring[15:0]), mem_col(dut.raw_ring[15:0]));
            end
        end
    end

    // ================= P101（#98 第二问：**链子的传递函数**，只打印不判定）=================
    // P100 已经量到：帧头 0..5 显示行上**原图抽头逐格等于定义、处理抽头恒等于源行 2**。
    //   两路吃的是同一个 `pix_raw`，所以病灶在 `u_pipe` 内部（它的行缓存/绕过 mux 在帧头怎么走的），
    //   不在地址侧。要把"内部哪一级开始重复"说出来，只需要链子**入口**的 (标签行, 内容 tag) 与
    //   **出口**的同一列对在一起 —— 入口在顶层第 3 级（`de_d[3]/x_d[3]/y_d[3]`，din = pix_raw），
    //   出口就是 P100 里那一列 `处理(行,列)`（同一列号 300，两处的数直接对着读）。
    integer p101_n = 0;
    always @(posedge dut.clk_pix) begin
        if (c5_on && dut.de_d[3] && dut.x_d[3] == 12'd300 && p101_n < 40 &&
            (dut.y_d[3] < 12'd12 || dut.y_d[3] >= 12'd588)) begin
            p101_n = p101_n + 1;
            $display("PROBE P101 链入口 y_d3=%0d cy_d3=%0d | din tag=(行%0d,列%0d) oob_fb=%b",
                     dut.y_d[3], dut.cy_d[3], mem_row(dut.pix_raw), mem_col(dut.pix_raw), dut.oob_fb_d1);
        end
    end

    // ---- C9（2026-09-27 23:3x 用户报的"效果开着时，跟着分割线走的一条黑线"）----
    //   为什么现有判据看不见它，两条都成立才怪：
    //     ① 台架把缝钉在 0 ⇒ 整屏只有处理抽头，"缝旁"那一档**结构上不存在**；
    //     ② `stage_sel` 全程 0（全旁路）⇒ 任何只在效果链开着时才坏的列都无从现形。
    //   所以这一段把缝挪到正中、只开灰度，并且**只看亮度不看 tag**：
    //   灰度把 RGB→亮度之后 tag 就不存在了，而图案每一格位 15 恒为 1 ⇒ 红通道最低也有 0xF8，
    //   灰度之后仍然远不是黑 ⇒ "画面内出现一整列近黑"就是缺陷本身，与它是什么颜色无关。
    //   成对写（本仓那条老规矩）：C9a 判"没有整列近黑"，C9b 判"确实有整列是亮的"——
    //   没有 C9b，C9a 的零可能只是探测器瞎了。
    localparam integer C9_SEAM = 512;
    integer c9_blk[0:1023], c9_rows = 0, c9_col = 0, c9_de_d = 0, c9_k = 0, c9_any = 0;
    integer c9_worst = 0, c9_wcol = -1, c9_best = 0, c9_bcol = -1, c9_border = 0;
    reg    c9_on = 1'b0;
    always @(posedge dut.clk_pix) begin
        if (dut.de_o && !c9_de_d) c9_col = 0;
        else if (dut.de_o) c9_col = c9_col + 1;
        if (c9_on && dut.de_o) begin
            if ((dut.r < 8'd16) && (dut.g < 8'd16) && (dut.b < 8'd16)) begin
                c9_blk[c9_col] = c9_blk[c9_col] + 1;
                c9_any = c9_any + 1;
            end
        end
        if (!dut.de_o && c9_de_d) c9_rows = c9_rows + 1;
        c9_de_d = dut.de_o;
    end

    function integer c4_ang_of; input integer a;
        begin
            case (a % 4) 0: c4_ang_of = 0;   1: c4_ang_of = 45;
                         2: c4_ang_of = 90; default: c4_ang_of = 168; endcase
        end
    endfunction
    // 这一档到底是几倍：由台架按**定义**报，不打印内部寄存器（Q8.8 的 inv 256 = 1.00x）。
    // 用它是因为报告里"0.50x 有没有背景带"这件事要一眼能读出来，而不是让明天的人去反推 index。
    function integer c4_pct_of; input integer a;
        begin
            case (a / 4) 0: c4_pct_of = 100;  1: c4_pct_of = 50;  default: c4_pct_of = 25;
            endcase
        end
    endfunction

    task line(input [8*96-1:0] tag, input ok, input [8*170-1:0] txt);
        begin
            if (!ok) nfail = nfail + 1;
            $display("%s %0s | %0s", ok ? "PASS" : "FAIL", tag, txt);
        end
    endtask

    initial begin
        for (i0 = 0; i0 < 6; i0 = i0 + 1) c1_kbad[i0] = 0;
        for (i0 = 0; i0 < 6; i0 = i0 + 1) c1_pbad[i0] = 0;
        // C5 的三条列账（2026-09-27 11:1x 的教训）：**标量 `integer` 的初值是 0，数组元素的初值是 X**
        //   ⇒ 不清零的 `c5_head_c[j5] = c5_head_c[j5] + 1` 永远是 X，而 `X > 5` 既不是真也不是假，
        //   `line()` 就在"算术上坏了"的基础上判红。这是本仓第七次撞"X 的出生地"，同族还有 #88。
        for (i0 = 0; i0 < 3; i0 = i0 + 1) begin
            c5_head_c[i0] = 0; c5_headbad_c[i0] = 0; c5_jud_c[i0] = 0; c5_badc_c[i0] = 0;
        end
        for (i0 = 0; i0 < 10; i0 = i0 + 1) c1_rdh[i0] = 0;
        for (i0 = 0; i0 < 16; i0 = i0 + 1) c1_rdbk[i0] = 0;
        c1_rdump = 0;
        for (i0 = 0; i0 < 14; i0 = i0 + 1) hist[i0] = 0;
        for (i0 = 0; i0 < 10; i0 = i0 + 1) begin hl_c[i0] = 0; hl_r[i0] = 0; end

        // ---- C0a 尺子校准：在任何测量之前先证明尺子对 ----
        //   #78 之后覆盖加宽：0 与"小列号"那一组是当年漏掉的（整数取位给 X 恰好不在 (200,177) 上出现），
        //   还有帧底/帧右两个边界（编码是 8 bit，299/511 会回绕，回绕方向也要一起验）。
        line("C0a ruler encodes position in the pixel", mem_row(px_val(200,177)) == 8'd72 && mem_col(px_val(200,177)) == 8'd177
             && px_val(0,0) == 16'h8000 && mem_row(px_val(0,2)) == 8'd0 && mem_col(px_val(0,2)) == 8'd2
             && mem_row(px_val(1,255)) == 8'd1  && mem_col(px_val(1,255)) == 8'hFF
             && mem_row(px_val(299,511)) == 8'd43 && mem_col(px_val(299,511)) == 8'd255
             && dsub(8'd2, 8'd254) == 4 && dsub(8'd254, 8'd2) == -4 && dsub(8'd0, 8'd255) == 1,
             "px_val / decoder / mod-256 signed diff must agree, incl. 0, small values, both edges, both wrap directions");
        // C0a3：**全帧 300×512 格没有一格编码成 16'h0000**。这条不是装饰：面板级尺子只能用
        // "是不是全黑"判断"在不在画面里"，只要图案里存在一个黑格，那条尺子就永远有假红可找。
        begin
            c0a3_black = 0;
            for (c0a3_r = 0; c0a3_r < 300; c0a3_r = c0a3_r + 1)
                for (c0a3_c = 0; c0a3_c < 512; c0a3_c = c0a3_c + 1)
                    if (px_val(c0a3_r, c0a3_c) == 16'h0000) c0a3_black = c0a3_black + 1;
        end
        line("C0a3 no black cell exists in the pattern", c0a3_black == 0,
             "the panel-level ruler equates black with outside-the-picture, so the pattern must not contain black");


        // ---- 复位释放 ----
        repeat (4) @(posedge sys_clk);
        sys_rst_n = 1; axi_rst_n = 1;
        repeat (10) @(posedge axi_clk);

        // ---- C0a2 模型回读（#78 新增的那一格）----
        //   放在复位之后再读：两个 initial 块（DDR 建模 vs 这一段）在 t=0 的先后是不确定的，
        //   而且"验函数"与"验被写进数组的东西"是两件事 —— 这次骗过所有人的正是后者。
        //   读首尾两格：尾格 (299,508..511) 同时钉住"行号 8 bit 回绕"与"数组最后一个字真的写到了"。
        //   读首尾两格：尾格 (299,508..511) 同时钉住"行号 8 bit 回绕"与"数组最后一个字真的写到了"。
        // ⚠ #92 那一轮把图案换成 `{1'b1, r[6:0], c[7:0]}`（位 15 当"非黑"标志）之后，**这两个字面量
        //   一直没跟着改** ⇒ 18:11 那一轮它红了，红的是尺子：判据里写的还是老编码
        //   （`0003_0002_0001_0000` / `2BFF_…`），而新图案第一字是 `8003_8002_8001_8000`、
        //   尾字是行 299 mod 128 = 43 = 0x2B 再并上位 15 ⇒ 0xABFF…。C0a 当时改了、C0a2 漏了。
        //   数按 `px_val` 手推（不是照抄实现），C0a 已经把"函数对不对"钉住，这里只补"数组里真的是它"。
        line("C0a2 golden array actually holds it", ddr[0] == 64'h8003_8002_8001_8000
             && ddr[FRAME_WORDS-1] == 64'hABFF_ABFE_ABFD_ABFC,
             "read back ddr[0] and the last word after init: a correct function is not a correct array");

        // ---- 跑到够帧数（发布位每帧翻一次，模拟"PS 每帧写完敲一次"） ----
        // 刻意**不用** fork/join_any/disable fork：那是 SystemVerilog 构造，而这份台架按 Verilog 编译。
        // 一次等"一帧的时间"再看帧计数，最多等 12 帧 ⇒ 天然有上界，不会挂死
        // （第一版 tb_v99 挂死那一课的教训：挂死的台架比红的台架糟，全量回归是顺序跑的）。
        i1 = 0;
        while (frames_done < FRAMES_MIN + 3 && i1 < 16) begin   // 多跑几帧：前 2 帧只用来让拷贝落地
            #(H_TOTAL * V_TOTAL * 20.0);          // 一帧 = 840000 拍 × 20 ns = 16.8 ms
            // 发布位由下面 `lm_hb` 那个进程统一翻（原来这里也翻一次：两个进程写同一根激励位
            // 就是"谁最后写算谁"，而 #94 之后这件事会直接决定屏幕画不画帧缓存 ⇒ 只留一个写者）
            i1 = i1 + 1;
        end

        $display("[tb_v98_top_seam.v:496] PROBE fb_wr_pulses=%0d (一帧要 %0d)  copy_hold 拍了 %0d  u_aw.active=%0d 最后到的 row=%0d",
                 fb_wr_pulses, FRAME_WORDS, hold_cyc, aw_active_cyc, last_row);
        $display("[tb_v98_top_seam.v:498] DIAG fb_vis=%0d owner_eth=%0d fill_busy=%0d row_busy=%0d eth_live=%0d tb_ok=%0d dbg_src=%04x tap_raw 全黑比例 %0d/%0d",
                 dut.fb_vis, dut.owner_eth, dut.fill_busy, dut.row_busy, eth_live, eth_tb_ok,
                 dbg_src, black_l, n_l);
        line("C0d a real source is on screen",
             n_l > 0 && black_l * 2 < n_l, "less than half of left-pane samples are black, else nothing was copied");
        line("C0b enough frames ran", frames_done >= FRAMES_MIN, "at least 3 frames, otherwise every count below is void");
        line("C0c the AXI copy is alive", ar_bursts > 100 && r_beats > 800 && odd_align == 0 && out_of_window == 0,
             "AXI bursts present, 8-byte aligned, never read outside the PS window");
        // ⚠ 这一条**降级为只报数**（当天第二次尺子先错，账记进 #68）：
        //   原来拿当拍的 sx_l（第 3 级地址）比当拍的标签，而这两者描述的不是同一个像素——
        //   标签描述的是 17 拍之前那个地址取回的内容。能真正判定标签与内容同列的只有两条路：
        //   ① 屏上是我喂的那张坐标图（内容判据，已在下面做成硬判据 C1a/C1b/C1c（探针先证伪了
        //      “没搬进来”那个解释，真正错的是尺子取错级数）；② 板上看缝左右 10 列有没有暗带
        //      （board/README.md 第 12 行，r59a 之后必看的眼睛判据）。
        //   留在这里当判据只会造出一条不可能成立的判据 ⇒ 打数、不判。
        $display("[tb_v98_top_seam.v:513] OBS C-tap 观测（不判定）：样本 %0d 格、偏差非零 %0d 格、首格偏差 %0d",
                 tap_cnt, tap_bad, tap_mode);
        $display("[tb_v98_top_seam.v:515] INFO C-tap 样本 %0d 格、偏 %0d 格、首格偏差 %0d（0 才是对的）",
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
        $display("[tb_v98_top_seam.v:529] X 读回 %0d 格，落在列 %0d..%0d；去重写过的字下标 %0d/38400",
                 nxread, xlo, xhi, wdistinct);
        // r59b-1 的核心主张，而且它**不需要**帧缓存里真有内容（只看顶层自己的两个同级标签）
        //   ⇒ 在 #54 那条"拷贝路径建模"补上之前，这一条就是新几何唯一能当场成立的机器判据。
        $display("[tb_v98_top_seam.v:533] 级数标定：源列 == 第 k 级显示列 >>1 的不符数（样本 %0d）", c1_n3);
        for (i0 = 0; i0 < 6; i0 = i0 + 1)
            $display("[tb_v98_top_seam.v:535] k=%0d 不符 %0d", i0, c1_kbad[i0]);
        // 标定实测（826259 格）：k=2 是唯一一处不符为 0 —— 这就是 mapper 那三级寄存器与
        //   `x_d[k] = x(T-1-k)` 这个下标约定的合力：mapper 输出 = 输入延迟 3 拍 = x_d[2]。
        //   写成 k=2 而不是"存在某个 k"：判据要能红，就必须钉死一个具体的级数（改几何时会红给它看）。
        // C1i：先要求"几何唯一级"存在，再要求**那一级**的相位不符数为 0（两级都靠测量，不靠字面量）。
        c1_kn = 0; c1_ktrue = 0;
        for (i0 = 0; i0 < 6; i0 = i0 + 1)
            if (c1_kbad[i0] == 0) begin c1_kn = c1_kn + 1; c1_ktrue = i0; end
        $display("[tb_v98_top_seam.v] OBS C1i 标定级数：几何 0 不符的 k 有 %0d 个（k=%0d），该级相位不符 %0d（其余级：k=2 相位 %0d）",
                 c1_kn, c1_ktrue, c1_pbad[c1_ktrue], c1_pbad[2]);
        line("C1i read-port phase same stage as src", c1_kn == 1 && c1_pbad[c1_ktrue] == 0,
             "col0/row0/pair_odd/req_vld must come from the calibrated label stage, not from a comment");
        line("C1g VIEWPORT col: src == x_d[2]>>1", c1_n3 > 50000 && c1_kbad[2] == 0,
             "single viewport: src column == display column >>1 at the calibrated stage (k=2 is the only zero)");
        $display("[tb_v98_top_seam.v:541] C1h 期望落在帧底夹紧行的格数 %0d、落在帧头绕回窗的格数 %0d；行不符 %0d",
                 c1_clamp, c1_wrapn, c1_geom_bad_row);
        line("C1h VIEWPORT row: src == wrap((y_d[2]+OFF+BILIN)>>1)", c1_geom_bad_row == 0 && c1_wrapn > 1000,
             "row-wise definition now includes the #97 frame-head wrap; floor c1_wrapn proves the wrap window was judged");
        $display("[tb_v98_top_seam.v:544] C1g/C1h 样本 %0d 格；列不符(旧口径) %0d", c1_n3, c1_geom_bad);
        $display("[tb_v98_top_seam.v:545] X 分层：有效拍 %0d | fb_rd 是 X 的 %0d | fb_pix_hold 是 X 的 %0d | fb_out 是 X 的 %0d",
                 n_blank, xr_rd, xr_hold, xr_out);
        line("C0e RULER self-consistent", n_l > 0 && bad_l >= hl_c[0],
             "out-of-range bucket must be a subset of the mismatch set");
        line("C1a content-check coverage", c1_n > 50000,
             "in-line left-pane samples below 50k means nothing was measured");
        $display("[tb_v98_top_seam.v:551] C1 样本 %0d 格（跳过出界/行首尾 %0d）；Δcol 首值 %0d、Δrow 首值 %0d、跳变 %0d 次",
                 c1_n, c1_skip, c1_fcol, c1_frow, c1_varies);
        // #78（2026-09-26 01:45）：这一段以前是"明知不成立所以只报数"，理由写的是
        //   "台架没把 DDR→显示帧缓存建模到位"。**那个理由错了**：真因是两个台架 bug
        //   （split_ctl 加宽到 19 位后台架还接 14 位 ⇒ 高位 Z ⇒ inv_used/sx/sy/rd_addr 全 X；
        //    以及 DDR 初始化里"一个表达式连调四次函数"在 xsim 给 X）。修完之后
        //   窗口内 X 占比实测 0/826259、Δcol 不符 0 ⇒ **X 前置与 Δcol 从今天起是硬判据**。
        //   行方向（01:58 也解释了，于是 C1d 同样是硬判据）：当年那 3704 个 Δrow≠0 **全是 +43**，
        //   而 43 = 0x2B = 299 的低 8 位 ⇒ 病不是地址、不是尺子，是**行环的开机热身**：一帧头
        //   OFF_LINES 个显示行里 `raw_line_delay` 装的还是上一帧尾部（旧状下地址夹在 299）那一行。
        //   #97 第四笔把帧尾那几个请求改成绕回（0,0,1,1）之后，这一族从"解释得通"升级成"逐格正确"：
        //   C1d-b 现在要求**每一个被跳过的帧头格子都解出本行自己要的那一源行**（见采样处注释），
        //   于是屏顶那几行不再只归眼睛 —— 板级项（`board/README.md` 第 33 行）退化成一次复核。
        //   跳过条件由 `u_pipe.OFF_LINES` 推出来（不写字面量 4），跳过的格数照 print，
        //   剩下的样本里 Δrow 必须为 0 —— 不是"允许 ±1"。
        //   ⚠ 走 `line()` 的 tag/说明**必须是 ASCII**：这个 task 的实参是定宽向量，而含 ≥0x80 字节的
        //   字符串一被赋给定宽向量就按字节砍掉 bit7（#55 记过），症状是判据名在日志里全是乱码 ——
        //   树上那些老 `line()` 就是这个形状，新写的两条改成 ASCII，中文放进直接的 $display（那条不截）。
        $display("[tb_v98_top_seam.v:564]        C1 样本 %0d 格（跳过出界/行首尾 %0d）；X 格 %0d；Δcol 不符 %0d、Δrow 不符 %0d；Δcol 首值 %0d、Δrow 首值 %0d、跳变 %0d 次",
                 c1_n, c1_skip, c1_hasx, c1_colbad, c1_rowbad,
                 c1_fcol, c1_frow, c1_varies);
        line("C1e PRECONDITION no X inside the measurement window", c1_hasx == 0,
             "with X present every dcol/drow below is false-green on an empty set (#78)");
        line("C1c content column == display column >> 1", c1_colbad == 0,
             "single-viewport geometry, content-level evidence (was a NOTE before #78)");
        $display("[tb_v98_top_seam.v:571] OBS C1d 行方向原始计数（硬判据在它下面一行）：Δrow 不符 %0d、跨帧恒定 = %0d",
                 c1_rowbad, (c1_varies == 0) ? 1 : 0);
        // #54 第 5 条解释完就转硬：跳过的两族例外都要见数（环热身 c1_ring、帧底夹紧 c1_clamp），
        //   剩下的样本里 Δrow 必须为 0 —— 不是"允许 ±1"，那一档放宽过就等于没有判据。
        line("C1d content row == display row >> 1 (outside ring warm-up)", c1_rowbad == 0,
             "row-wise content alignment of the raw tap; warm-up rows are counted, not hidden");
        $display("C1d 例外计数：行环热身跳过 %0d 格（其中可判 %0d 格）、期望落在帧底夹紧 %0d 格（照判不跳过）、出界/行首尾跳过 %0d 格",
                 c1_ring, c1_ring_n, c1_clamp, c1_skip);
        // 例外自己也要被验一遍 —— 但这一族的验法**换了地方**：本轮把这句话从"必须等于 43（病灶）"
        //   改成"必须等于本行自己要的那一源行"（正名）之后，地板量出来 `c1_ring = 0`
        //   ⇒ 这一族的样本**一直是空的**：C1 的采样窗要求列在 [25,487]（行标签与内容在行首不同行），
        //   实测"行标签 < OFF+2 且列在那一窗"这一组合一次都没成立过（本轮 c1_ring=0），
        //   也就是帧头那几格从来没进过 C1 的账 —— 为什么没进账不重要，重要的是它没进。
        //   所以旧版那条 `C1d-b PASS` 是**空集上的绿**（本仓记到第五次的同一族），
        //   而它这次红了 —— 红得对，只是红的位置该改：判"帧头内容"的活儿由 **C5c** 干，
        //   而且从今天起 C5c 在缝的两侧各采一列（原图那一路与处理那一路是两件不同的事）。
        //   这里只留 OBS + 计数，不留一条永远不会红的判据。
        $display("OBS C1d-b (retired): warm-up branch samples = %0d (judged %0d, unexplained %0d) => 空集，判据搬到 C5c",
                 c1_ring, c1_ring_n, c1_ring_unexpl);
        // Δrow 的形状（#54 第 5 条）：值分布 + 列分布 + 原始样本，三样一起看才知道该修谁
        $display("ROWMIX values drow=-4..+3 | big+ big- : %0d %0d %0d %0d %0d %0d %0d %0d | %0d %0d",
                 c1_rdh[0], c1_rdh[1], c1_rdh[2], c1_rdh[3], c1_rdh[4], c1_rdh[5], c1_rdh[6],
                 c1_rdh[7], c1_rdh[8], c1_rdh[9]);
        $display("ROWMIX cols bucket=32 (0..7): %0d %0d %0d %0d %0d %0d %0d %0d",
                 c1_rdbk[0], c1_rdbk[1], c1_rdbk[2], c1_rdbk[3], c1_rdbk[4], c1_rdbk[5],
                 c1_rdbk[6], c1_rdbk[7]);
        $display("ROWMIX cols bucket=32 (8..15): %0d %0d %0d %0d %0d %0d %0d %0d",
                 c1_rdbk[8], c1_rdbk[9], c1_rdbk[10], c1_rdbk[11], c1_rdbk[12], c1_rdbk[13],
                 c1_rdbk[14], c1_rdbk[15]);
        $display("[tb_v98_top_seam.v:573] 观测（老尺子，仅供以后对比）：左窗 n=%0d 不符=%0d；右窗列不符=%0d",
                 n_l, bad_l, bad_r_col);
        // ⚠ 这一条原来写的是 `... 恒定 = %0s ...", m2_mode, (m2_varies==0)?"是":"否", n_r` ——
        //   三元式里两个字符串字面量在 Verilog 里会**折成较短操作数的位宽**（实测：整行输出成乱码，
        //   连前面的 `%0d` 都被带歪），所以这里一律改成数字 + 单独一句中文说明。
        //   见 `skill/bench_verilog_subset.md` 第 9 类。
        $display("[tb_v98_top_seam.v:579] M2 右窗行偏移（全旁路，今天只报数）：众数=%0d 变化次数=%0d 样本=%0d",
                 m2_mode, m2_varies, n_r);
        for (i0 = 0; i0 < 14; i0 = i0 + 1)
            if (hist[i0] != 0) $display("[tb_v98_top_seam.v:582] Δrow%0d : %0d 点", i0 - 7, hist[i0]);
        // 左窗的两条直方图 = **尺子诊断**：如果 Δ 全挤在 +1/-1 或奇偶两格，那是映射/相位/端序的问题，
        // 不是硬件错位；如果是一条宽分布，才是真的没对齐。
        for (i0 = 1; i0 < 10; i0 = i0 + 1)
            if (hl_c[i0] != 0) $display("[tb_v98_top_seam.v:586] 左窗 Δcol%0d : %0d 点", i0 - 5, hl_c[i0]);
        for (i0 = 1; i0 < 10; i0 = i0 + 1)
            if (hl_r[i0] != 0) $display("[tb_v98_top_seam.v:588] 左窗 Δrow%0d : %0d 点", i0 - 5, hl_r[i0]);
        if (hl_c[0] != 0) $display("[tb_v98_top_seam.v:589] 左窗 Δcol 超出±5 : %0d 点（量程不够 / 内容根本不是这张图）", hl_c[0]);
        if (hl_r[0] != 0) $display("[tb_v98_top_seam.v:590] 左窗 Δrow 超出±5 : %0d 点", hl_r[0]);
        $display("[tb_v98_top_seam.v:591] ⇒ 非 0 是**已知的**：`cy_r` 提前 OFF_LINES 行补的是链子内容滞后，全旁路时链子不滞后。");
        $display("[tb_v98_top_seam.v:592] V8-4b（单流 + 链前/链后两抽头）之后这一格必须是 0，届时把 M2 转成硬判据。");
        // ⚠ 原来这一条写成 `line("M3 ...", m2_varies == 0 || 1'b1, ...)` —— 那个 `|| 1'b1`
        //   使它**永远不可能红**，是仓库自己定的规矩里明令禁止的"假判据"（见
        //   `skill/bench_self_inflicted_reds.md`）。今天右窗的内容期望还没修对（见上面 C1/C2 那段），
        //   所以这里**没有任何一条**关于行偏移的判据能成立 ⇒ 老老实实只报数，
        //   等 C1/C2 的前置条件（两个自相矛盾的计数器先一致）满足后，再把"跨帧恒定 + 恒等于 +OFF_LINES"
        //   一起转成硬判据 —— 那时它才有可能是红的。
        $display("[tb_v98_top_seam.v:599] OBS M3 右窗行偏移跨帧是否恒定（不判定，内容期望未修对）：恒定 = %0d（1=恒定，0=一帧一变），变化次数 %0d",
                 (m2_varies == 0) ? 1 : 0, m2_varies);
        $display("[tb_v98_top_seam.v:601] INFO 统计 frames=%0d ar=%0d r=%0d odd=%0d outwin=%0d n_l=%0d bad_l=%0d n_r=%0d bad_r_col=%0d",
                 frames_done, ar_bursts, r_beats, odd_align, out_of_window, n_l, bad_l, n_r, bad_r_col);
        // ================= C2：八档缩放全扫，量"画面比几何偏了几列"（#92）=================
        // 上面一整轮 C1 判据的期望是按 **1.00x 手动档**写的（`zoom_sel=4`），那一档画面正好铺满
        // 整屏 ⇒ 没有背景带可量。0.50x 时画面只该占 x∈[256,767]，两侧各 256 列背景 ⇒
        // #92 的"贴边那一线"就在这里现形，并且报出来是**几列**（用户说肉眼量不出来）。
        // ============================ C4（#93 的尺子，先量后修）============================
        // 放在 C2 之前、且**自己把设置还回去**：C2 那八档的数是 r74/r75 门禁第 15 项的凭据，
        // 一个字符都不许被这一轮动到。这一轮只**报数 + 判形状**，不碰 RTL（用户 2026-09-26 17:0x
        // 的原话是"你先别修，先把这条记下来"，而 #93 的 (C) 段说的就是"先有这把尺子"）。
        split_ctl_tb[13] = 1'b1;             // 缝标记关掉：不然"第二段"就是台架自己画的那条蓝线
        bilin_en_tb      = 1'b0;             // 最近邻：插值会把两格的 tag 混成第三格，形状判据不需要它
        zoom_en = 1'b1; zoom_manual = 1'b1;              // 倍率由下面每一档自己钉，别让呼吸把期望漂走
        for (c4_a = 0; c4_a < C4_NA; c4_a = c4_a + 1) begin
            case (c4_a % 4)
                0: force dut.angle = 9'd0;
                1: force dut.angle = 9'd45;
                2: force dut.angle = 9'd90;
                default: force dut.angle = 9'd168;
            endcase
            // 强设不是 snap 过的：等它稳定，别采到换角那一帧。`angle==0` 时把 rot_on 关掉，
            // 与 C1 阶段那个"没旋转"的世界同形。
            force dut.rot_on = ((c4_a % 4) == 0) ? 1'b0 : 1'b1;
            case (c4_a / 4)
                0:   zoom_sel = 3'd4;          // inv 256  = 1.00x：无背景带，本维结构上看不见细线
                1:   zoom_sel = 3'd2;          // inv 512  = 0.50x：两侧各 256 列背景
                default: zoom_sel = 3'd0;      // inv 1023 = 0.25x：两侧各 384 列背景（最敏感的一档）
            endcase
            repeat (3) @(posedge dut.frame_start);
            c4_on = 1'b1;
            repeat (2) @(posedge dut.frame_start);
            c4_on = 1'b0;
            // 无画面行**只报不判**：0.50x/0.25x 画面只占 300/150 行高，屏上下各有一带黑的行是**对的**。
            // 判的只有两件事：这一档真有足够多的行被量到（覆盖地板），以及每一行至多一段。
            $display("C4 idx=%0d ang=%0d zoom=%0d%% zsel=%0d 有画面行=%0d 无画面行=%0d **多段行=%0d** 第1列[%0d..%0d] 末列[%0d..%0d] | angle=%0d rot_on=%b",
                     c4_a, c4_ang_of(c4_a), c4_pct_of(c4_a), zoom_sel,
                     c4_rows2[c4_a], c4_zero[c4_a], c4_bad[c4_a],
                     c4_fmin[c4_a], c4_fmax[c4_a], c4_lmin[c4_a], c4_lmax[c4_a],
                     dut.angle, dut.rot_on);
            // 覆盖地板：没有 200 行的话，下面那条"每行一段"就是空集上的绿（#60 那一课）
            line("C4a rows judged", c4_rows2[c4_a] > 200,
                 "this (angle, zoom) cell must actually have content rows, else C4b below means nothing");
            line("C4b one run per row", c4_bad[c4_a] == 0,
                 "a rotated rectangle meets every panel row in ONE contiguous run; 2+ runs = #93's stray diagonal bar / left-edge line");
        end
        // ---- C5（#97 追加二：行维）----
        $display("C5  judged=%0d bad=%0d | head rows=%0d wrong=%0d (OFF_LINES=%0d, col=%0d)",
                 c5_judged, c5_bad, c5_head, c5_head_bad, c5_off, C5_COL);
        line("C5a judged rows", c5_judged > 500,
             "the 0deg x 100% cell must give >=500 judged rows, else C5b/C5c below mean nothing");
        line("C5b body rows carry their own source row", c5_bad == 0,
             "decoded tag row == panel row/2 below the pipeline head; any off-by-N is the read-side advance (cy_r)");
        $display("C5 分列（帧头窗 = 最上面 OFF+2 行）：col%0d 头 %0d 格/不符 %0d、体 %0d 格/不符 %0d || col%0d 头 %0d/%0d、体 %0d/%0d || col%0d 头 %0d/%0d、体 %0d/%0d",
                 C5_LA, c5_head_c[0], c5_headbad_c[0], c5_jud_c[0], c5_badc_c[0],
                 C5_COL, c5_head_c[1], c5_headbad_c[1], c5_jud_c[1], c5_badc_c[1],
                 C5_RA, c5_head_c[2], c5_headbad_c[2], c5_jud_c[2], c5_badc_c[2]);
        line("C5c frame head is not the previous frame's tail",
             c5_head_bad == 0 && c5_head_c[0] > 5 && c5_head_c[1] > 5 && c5_head_c[2] > 5,
             "first OFF+BILIN output rows must carry their own source row on BOTH sides of the seam");
        $display("C6  每行第0格 judged=%0d 源列不是0的=%0d", c6_n, c6_bad);
        line("C6a line head carries the line's own column 0", c6_n > 500 && c6_bad == 0,
             "at 0deg x 100% the picture fills the screen, so NO background-based ruler can see a wrapped line head; the tag's column must be 0 (= #97's left band candidate)");
        // ---- C8（#102）：两路抽头各自的"每行第一格"，本体行窗 ----
        $display("C8  第0列：原图 样本 %0d 格、不符 %0d 格 || 处理 样本 %0d 格、不符 %0d 格",
                 c8_os, c8_ob, c8_ps, c8_pb);
        line("C8a raw tap's first column of every body row is the row's own column 0",
             c8_os > 500 && c8_ob == 0,
             "#102：行环在行首读到的是消隐期那个地址的格子（实测=源列 160），不是本行第一列");
        line("C8b proc tap's first column of every body row is the row's own column 0",
             c8_ps > 500 && c8_pb == 0,
             "同一格在处理抽头上的对照面：C8a 绿而屏上仍有线时，问题就落在这一路");
        release dut.angle;
        release dut.rot_on;
        c4_on = 1'b0;
        force dut.angle = 9'd0;                // 还回 C1 阶段那个"没旋转"的世界，再让 angle_ctrl 接管
        release dut.angle;
        repeat (2) @(posedge dut.frame_start);
        split_ctl_tb[13] = 1'b0;
        bilin_en_tb      = 1'b1;
        zoom_en = 1'b0; zoom_sel = 3'd4;
        repeat (2) @(posedge dut.frame_start);
        zoom_en     = 1'b1;                  // 顶层的 enable 门：不打开，zoom_ctrl 根本不换倍率
        zoom_manual = 1'b1;                  // 停在手动档，别让呼吸把期望漂走
        // C3 要把那条 2 px 标记线关掉（见上面 C3 注释第 ② 条）：缝位=0 时它正好落在屏上最左几列，
        // 不关掉的话"屏上第一个非黑列"量的就是台架自己画的蓝线。C2 不受影响（它看的是 mux 之前的 sel）。
        split_ctl_tb[13] = 1'b1;             // = `split marker 0`
        // 这一轮量的是**几何** ⇒ 走最近邻。双线性按定义会把相邻两格的 16 位 tag 混成第三格，
        // 那时 C2b"这一格该解出定义要的那个源列"永远成立不了（bilin=1 时 inv=1023 那档
        // inbad = 68920/77400 = 89 % —— 那是插值，不是错位；尺子不许把别人的活计判成红）。
        bilin_en_tb = 1'b0;
        repeat (2) @(posedge dut.frame_start);
        // ---- C9（用户 2026-09-27 23:3x 报的那一条）：缝挪到正中 + 只开灰度 ----
        //   为什么这一档以前必然看不见它：① 缝在 0 ⇒ "缝旁"那一档在屏上不存在；
        //   ② `stage_sel` 全程 0 ⇒ 只在效果开着时才坏的列无从现形。两条都是台架的窗，不是设计无辜。
        for (c9_k = 0; c9_k < 1024; c9_k = c9_k + 1) c9_blk[c9_k] = 0;  // ⚠ `integer` 数组的初值是 X，必须清（#94 那一族）
        c9_rows = 0; c9_col = 0; c9_de_d = 0; c9_any = 0;
        split_ctl_tb[9:0] = 10'd512;          // 缝在正中：左半原图、右半处理（不写 C9_SEAM[9:0]：对无位宽参数做部分选择不稳）
        stage_sel         = 9'd1;             // 只开灰度 = 用户念的 `pipe 100000000`
        repeat (3) @(posedge dut.frame_start);   // 等 sel_sync 与缝的 snap 都落定，别采到换档那一帧
        c9_on = 1'b1;
        repeat (2) @(posedge dut.frame_start);
        c9_on = 1'b0;
        stage_sel = 9'd0;
        split_ctl_tb[9:0] = 10'd0;            // 全部还回去：C2/C3/C7 已有的数不能被这一档重定基线
        repeat (2) @(posedge dut.frame_start);
        c9_worst = 0; c9_wcol = -1; c9_best = 999999; c9_bcol = -1;
        for (c9_k = 1; c9_k < 1023; c9_k = c9_k + 1) begin
            if (c9_blk[c9_k] > c9_worst) begin c9_worst = c9_blk[c9_k]; c9_wcol = c9_k; end
            if (c9_blk[c9_k] < c9_best)  begin c9_best  = c9_blk[c9_k]; c9_bcol  = c9_k; end
        end
        $display("C9  灰度 x 缝=%0d：判 %0d 行、近黑格 %0d || 最暗列 col%0d=%0d 行、最亮列 col%0d=%0d 行 || 缝旁 col%0d=%0d col%0d=%0d col%0d=%0d",
                 C9_SEAM, c9_rows, c9_any, c9_wcol, c9_worst, c9_bcol, c9_best,
                 C9_SEAM-1, c9_blk[C9_SEAM-1], C9_SEAM, c9_blk[C9_SEAM], C9_SEAM+1, c9_blk[C9_SEAM+1]);
        line("C9pre rows judged", c9_rows >= 550,
             "this window must have judged nearly the whole frame, else C9a below is a green on an empty set");
        line("C9a no full-height black column with gray on and seam mid", c9_worst * 2 < c9_rows,
             "the line the user reported at 23:3x: no column inside the picture may be majority near-black");
        line("C9c columns at the seam are not black either",
             (c9_blk[C9_SEAM-1] * 2 < c9_rows) && (c9_blk[C9_SEAM] * 2 < c9_rows) &&
             (c9_blk[C9_SEAM+1] * 2 < c9_rows),
             "the user says the line appears where the divider passes; the seam's own columns are the suspect set");
        // ---- C9b：把**同一把尺子**拿到"已知有一条条黑列"的那一档去，它必须数到东西 ----
        // 原来这一格判的是"最亮列几乎全亮"，而 best 的初值就是 0 ⇒ 探测器全瞎也照样 PASS，
        // 也就是说 C9a 的那个 0 从来没被证明不是瞎。这一档改成"必须数到黑"（0.50x 有背景带）。
        for (c9_k = 0; c9_k < 1024; c9_k = c9_k + 1) c9_blk[c9_k] = 0;
        c9_rows = 0; c9_col = 0; c9_de_d = 0; c9_any = 0;
        stage_sel  = 9'd5;                    // 灰度 + 模糊：这一档顺带覆盖"窗口级开着"的情形
        zoom_sel   = 3'd2;                    // 0.50x ⇒ 左右各 256 列黑背景（C4 那一维量过）
        split_ctl_tb[9:0] = 10'd512;
        repeat (3) @(posedge dut.frame_start);
        c9_on = 1'b1;
        repeat (2) @(posedge dut.frame_start);
        c9_on = 1'b0;
        stage_sel = 9'd0;
        zoom_sel  = 3'd4;
        split_ctl_tb[9:0] = 10'd0;            // 还回去：后面的 C2/C3/C7 不能被这一档重定基线
        c9_border = 0;
        for (c9_k = 1; c9_k < 1023; c9_k = c9_k + 1)
            if (c9_blk[c9_k] * 2 >= c9_rows) c9_border = c9_border + 1;
        $display("C9b 0.50x gray+blur: rows %0d near-black cells %0d || whole-dark columns %0d (border should give ~512)",
                 c9_rows, c9_any, c9_border);
        line("C9bpre rows judged", c9_rows >= 550,
             "the control window must have judged nearly a whole frame, else C9b means nothing");
        line("C9b detector does see known black columns", c9_border >= 100,
             "pair for C9a: on a cell where a dark column is guaranteed, this same counter must light up");

        $display("C2 table  code inv  nin     nout     inbad viol measl measr geol geor leakl leakr blank invbad | C3 rows empt wbad rbad fmin fmax lmin lmax");
        for (c2_k = 4'd0; c2_k < 4'd8; c2_k = c2_k + 4'd1) begin
            zoom_sel = c2_k[2:0];
            repeat (3) @(posedge dut.frame_start);      // 准静态量：跨几帧再采，别采到换档那一拍
            c2_on = 1'b1;
            repeat (2) @(posedge dut.frame_start);
            c2_on = 1'b0;
            // 每一档**当场**把数与判据打出来：整轮八档要 40 帧（一个多小时），
            // 攒到最后才打就等于"要等一小时才知道尺子对不对"（#88 那一轮就是这么过的）。
            $display("C2 row    %0d %4d %8d %8d %6d %4d %5d %5d %4d %4d %5d %5d %5d %4d | %4d %4d %3d %3d %4d %4d %4d %4d",
                     c2_k, C2_TBL(c2_k), c2_nin[c2_k], c2_nout[c2_k], c2_inbad[c2_k], c2_viol[c2_k],
                     c2_measl[c2_k], c2_measr[c2_k], c2_geol[c2_k], c2_geor[c2_k],
                     c2_leakl[c2_k], c2_leakr[c2_k], c2_blank[c2_k], c2_invbad[c2_k],
                     c3_rows[c2_k], c3_empty[c2_k], c3_wbad[c2_k], c3_rbad[c2_k],
                     c3_fmin[c2_k], c3_fmax[c2_k], c3_lmin[c2_k], c3_lmax[c2_k]);
            // 坏格的**列对形状**当场算清（484 这种总数只说"每行错几格"，不说错在哪一对；
            // 行尾 / 行首 / 中间 是三套完全不同的修法，留给下一轮猜就是再花两小时）。
            c2_ib_np = 0; c2_ib_f = -1; c2_ib_l = -1;
            for (c2_ib_q = 0; c2_ib_q < 512; c2_ib_q = c2_ib_q + 1)
                if (c2_ibv[c2_k][c2_ib_q]) begin
                    c2_ib_np = c2_ib_np + 1;
                    if (c2_ib_f < 0) c2_ib_f = c2_ib_q;
                    c2_ib_l = c2_ib_q;
                end
            $display("C2SHAPE code=%0d inv=%0d inbad=%0d badpairs=%0d firstpair=%0d lastpair=%0d dm1=%0d dp1=%0d dother=%0d",
                     c2_k, C2_TBL(c2_k), c2_inbad[c2_k], c2_ib_np, c2_ib_f, c2_ib_l,
                     c2_dm1[c2_k], c2_dp1[c2_k], c2_doth[c2_k]);
            // ---- C7（#102）：同一点、同一拍，比的是**行**那一半位 ----
            c7_np = 0; c7_f = -1; c7_l = -1;
            for (c7_q = 0; c7_q < 512; c7_q = c7_q + 1)
                if (c7_rbv[c2_k][c7_q]) begin
                    c7_np = c7_np + 1;
                    if (c7_f < 0) c7_f = c7_q;
                    c7_l = c7_q;
                end
            $display("C7 row    code=%0d inv=%0d rn=%0d rblk=%0d rbad=%0d badpairs=%0d firstpair=%0d lastpair=%0d dm1=%0d dp1=%0d dother=%0d",
                     c2_k, C2_TBL(c2_k), c7_rn[c2_k], c7_rblk[c2_k], c7_rbad[c2_k], c7_np, c7_f, c7_l,
                     c7_rm1[c2_k], c7_rp1[c2_k], c7_rbad[c2_k] - c7_rm1[c2_k] - c7_rp1[c2_k]);
            line("C7pre sampled", c7_rn[c2_k] > 20000 && c7_rblk[c2_k] < 20000,
                 "the row ruler needs samples in the SAME window C2 judges (rblk<20000 = 采样带纵向没跑出画面)");
            line("C7 row matches definition", c7_rbad[c2_k] == 0,
                 "each sampled cell must decode to the source ROW the definition asks for, all 8 zoom steps");
            line("C2pre inv took", c2_invbad[c2_k] == 0 && c2_nin[c2_k] > 20000,
                 "inv_used must equal the table value, and the code must have been sampled");
            line("C3pre marker off", dut.split_marker_on === 1'b0,
                 "the 2px seam marker would itself be a non-black column at the panel edge (#92)");
            line("C3a panel active window", c3_wbad[c2_k] == 0 && c3_rbad[c2_k] == 0,
                 "every measured line must be exactly 1024 de-high columns and the frame 600 lines");
            line("C3b panel rows judged", c3_rows[c2_k] > 100,
                 "C3 must actually have content rows to judge, else the edge numbers below are void");
            // ① 倍率真的吃进去了 ② 背景里不许有内容 ③ 画面内不许有黑格
            line("C2a bg black", c2_viol[c2_k] == 0 && c2_blank[c2_k] == 0,
                 "no content in background / no black hole inside the picture");
            line("C2b col matches definition", c2_inbad[c2_k] == 0,
                 "each in-window column must decode to the source column the definition asks for");
            line("C2c edges match definition", c2_leakl[c2_k] < 0 && c2_measl[c2_k] == c2_geol[c2_k]
                 && c2_measr[c2_k] == c2_geor[c2_k],
                 "measured picture edges == geometric edges (content stage, in columns)");
            // 面板级同一件事：屏上画面的左右沿必须落在定义说的那两列，而且**逐行一致**
            //（fmin!=fmax 就是"这一行的边在抖"，那是另一种病，不许用区间糊过去）。
            line("C3c panel edges match definition", c3_fmin[c2_k] == c3_fmax[c2_k]
                 && c3_lmin[c2_k] == c3_lmax[c2_k]
                 && c3_fmin[c2_k] == c2_geol[c2_k] && c3_lmax[c2_k] == c2_geor[c2_k],
                 "the panel's own first/last non-black column == the geometric edges, same on every row");
            // _coverage floor_：背景侧只在有背景的档（inv>=341，即 code 0..3）要求样本数，
            //   1.00x 与放大档本来就没有背景列 —— 那种档要求 nout>0 会永远是 0，等于假红。
            if (c2_k < 4'd4)
                line("C2d coverage", c2_nout[c2_k] > 20000 && c2_nin[c2_k] > 20000,
                     "zoom-out codes must actually have background columns to judge");
        end
        zoom_en  = 1'b0;                     // 还回 C1 阶段那对值：复跑/对照不许被这一轮改动
        zoom_sel = 3'd4;
        split_ctl_tb[13] = 1'b0;             // 标记线也还回去（与 C1 阶段同一个形状）
        bilin_en_tb = 1'b1;
        // P1 的账（报数，不判红）：arm 应当约等于"行数 × 帧数"，flush 与 arm 同量级才说明
        // 顶层真的多跳了那一拍；p_piped 与 p_mixde 差多少 = 链子的 de 与混色级取的标签差几拍。
        $display("P1 chain-blur: arm(x==1023&de)=%0d flush=%0d run@行尾 min=%0d max=%0d | pipe_de=%0d mix_de_d11=%0d (差 %0d)",
                 p_arm, p_flush, p_runmin, p_runmax, p_piped, p_mixde, p_piped - p_mixde);
        if (nfail == 0) $display("RESULT tb_v98_top_seam PASS");
        else            $display("RESULT tb_v98_top_seam FAIL nfail=%0d", nfail);
        $finish;
    end
endmodule
