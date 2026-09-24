`timescale 1ns/1ps
// system_top — ghosting-fix v5 (same pins as src)
module system_top (
    inout  wire        DDR_cas_n,
    inout  wire        DDR_cke,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cs_n,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire [2:0]  DDR_ba,
    inout  wire [14:0] DDR_addr,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dm,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,
    input  wire        sys_clk,
    input  wire        key1_n,
    input  wire        key2_n,
    output wire [1:0]  led,
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n,
    input  wire        eth_rxc,
    input  wire        eth_rx_ctl,
    input  wire [3:0]  eth_rxd,
    output wire        eth_tx_clk,
    output wire        eth_tx_ctl,
    output wire [3:0]  eth_txd,
    output wire        eth_mdc,
    inout  wire        eth_mdio,
    output wire        eth_rst_n
);
    wire fclk0, fclk0_rst_n;
    wire [31:0] gpio_o, status;
    wire [31:0] gpio1_i;   // v7.6：PL→PS 的健康 lane 窗口（BD 的 GPIO_1 输入）
    // V8-2：新的效果/几何控制字（BD 里第二个 AXI GPIO，2 通道 × 32 bit，纯输出）。
    //   ch1[8:0] = stage_sel（九位算法选择，见 proc_pipeline.v 文件头）
    //   ch1[31:9] 与 ch2 全留给 V8-3/Gamma 与 V8-4/分割线 —— 现在**故意不接**：
    //   地址与通道布局一次定好，后面两步就不用再动 BD（动一次 BD = 全套门禁重来）。
    wire [31:0] gpio_cfg1_o, gpio_cfg2_o;
    wire [31:0] m_araddr;
    wire [5:0]  m_arid;
    wire [3:0]  m_arlen_axi3;
    wire [2:0]  m_arsize;
    wire [1:0]  m_arburst;
    wire        m_arvalid, m_arready;
    wire [63:0] m_rdata;
    wire [5:0]  m_rid;
    wire [1:0]  m_rresp;
    wire        m_rlast, m_rvalid, m_rready;
    wire [7:0]  m_arlen8;

    wire [31:0] m_awaddr;
    wire [7:0]  m_awlen;
    wire [2:0]  m_awsize;
    wire [1:0]  m_awburst;
    wire        m_awvalid, m_awready;
    wire [63:0] m_wdata;
    wire [7:0]  m_wstrb;
    wire        m_wlast, m_wvalid, m_wready;
    wire        m_bvalid, m_bready;
    wire [3:0]  m_awlen_axi3 = m_awlen[3:0];

    design_1_wrapper u_bd (
        .DDR_cas_n(DDR_cas_n), .DDR_cke(DDR_cke), .DDR_ck_n(DDR_ck_n), .DDR_ck_p(DDR_ck_p),
        .DDR_cs_n(DDR_cs_n), .DDR_odt(DDR_odt), .DDR_ras_n(DDR_ras_n), .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n), .DDR_ba(DDR_ba), .DDR_addr(DDR_addr), .DDR_dq(DDR_dq),
        .DDR_dm(DDR_dm), .DDR_dqs_n(DDR_dqs_n), .DDR_dqs_p(DDR_dqs_p),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn), .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio), .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb), .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        .FCLK_CLK0(fclk0), .FCLK_RESET0_N(fclk0_rst_n),
        .GPIO_0_tri_o(gpio_o),
        .GPIO_1_tri_i(gpio1_i),
        .GPIO_2_tri_o(gpio_cfg1_o),
        .GPIO_3_tri_o(gpio_cfg2_o),
        .M_AXI_HP0_araddr(m_araddr), .M_AXI_HP0_arburst(m_arburst),
        .M_AXI_HP0_arcache(4'b0011), .M_AXI_HP0_arid(m_arid),
        .M_AXI_HP0_arlen(m_arlen_axi3), .M_AXI_HP0_arlock(2'b00),
        .M_AXI_HP0_arprot(3'b000), .M_AXI_HP0_arqos(4'b0000),
        .M_AXI_HP0_arready(m_arready), .M_AXI_HP0_arsize(m_arsize),
        .M_AXI_HP0_arvalid(m_arvalid),
        .M_AXI_HP0_awaddr(m_awaddr), .M_AXI_HP0_awburst(m_awburst), .M_AXI_HP0_awcache(4'b0011),
        .M_AXI_HP0_awid(6'd0), .M_AXI_HP0_awlen(m_awlen_axi3), .M_AXI_HP0_awlock(2'b00),
        .M_AXI_HP0_awprot(3'b000), .M_AXI_HP0_awqos(4'b0000),
        .M_AXI_HP0_awready(m_awready), .M_AXI_HP0_awsize(m_awsize),
        .M_AXI_HP0_awvalid(m_awvalid),
        .M_AXI_HP0_bid(), .M_AXI_HP0_bready(m_bready), .M_AXI_HP0_bresp(), .M_AXI_HP0_bvalid(m_bvalid),
        .M_AXI_HP0_rdata(m_rdata), .M_AXI_HP0_rid(m_rid), .M_AXI_HP0_rlast(m_rlast),
        .M_AXI_HP0_rready(m_rready), .M_AXI_HP0_rresp(m_rresp), .M_AXI_HP0_rvalid(m_rvalid),
        .M_AXI_HP0_wdata(m_wdata), .M_AXI_HP0_wid(6'd0), .M_AXI_HP0_wlast(m_wlast),
        .M_AXI_HP0_wready(m_wready), .M_AXI_HP0_wstrb(m_wstrb), .M_AXI_HP0_wvalid(m_wvalid)
    );

    assign m_arlen_axi3 = m_arlen8[3:0];

    reg [23:0] phy_rst_cnt = 24'd0;
    always @(posedge sys_clk) begin
        if (!(&phy_rst_cnt)) phy_rst_cnt <= phy_rst_cnt + 1'b1;
    end
    assign eth_rst_n = phy_rst_cnt[23];
    assign eth_mdio  = 1'bz;
    assign eth_mdc   = 1'b0;

    wire clk_pix_unused, clk_pix5x_unused, mmcm_locked;
    wire clk_200m;
    clk_gen u_idelay_clkgen (
        .clk_in(sys_clk), .rst_n(1'b1),
        .clk_pix(clk_pix_unused), .clk_pix5x(clk_pix5x_unused),
        .clk_200m(clk_200m), .locked(mmcm_locked)
    );

    wire        eth_wr_en, eth_frame_done, eth_link;
    wire [18:0] eth_wr_addr;
    wire [15:0] eth_wr_data;
    wire [31:0] eth_frames, eth_pkts, eth_bytes, eth_bad;
    // ---- V7.9.6（P0-C ③）：几何与 DDR 基址只在这里出现一次 ----
    // 原来 512/300/0x1000_0000 在下面两个例化上各写一遍字面量。两个模块自己都有 parameter，
    // 但**没有任何东西阻止两边不一致** —— 而一旦不一致，现象是"写进去的帧几何与读出来的
    // 显示几何对不上"（整幅画面错位/撕裂），既不是综合错误也不是仿真必红。
    // 换分辨率因此从"全文搜字面量"变成"改这四行"。
    localparam [15:0] VIDEO_W    = 16'd512;      // 帧缓冲宽（像素）
    localparam [15:0] VIDEO_H    = 16'd300;      // 帧缓冲高（行）
    localparam [15:0] PANE_W     = 16'd512;      // 右半窗宽（当前与 VIDEO_W 同值，语义不同）
    localparam [31:0] DDR_BASE   = 32'h1000_0000;
    // PS 片源（SD 回放 / FILL）专用的第三个 DDR bank。ETH 占 0x1000_0000 与 0x1008_0000
    // 乒乓两 bank（每帧 300 KB，间隔 512 KB 够用），所以第三个 bank 从 +1 MB 起。
    // 这个数**必须与固件里的 FRAME_ADDR 一致**：`src/ps/sd_play.c` 与 `src/ps/main.c`
    // 各有一处，改这里不改那边 ⇒ 现象是"PS 片源在屏上不动"（搬运机读的是另一块内存）。
    localparam [31:0] PS_DDR_BASE = 32'h1010_0000;
    localparam [15:0] UDP_VIDEO_PORT = 16'd5001; // PC 推流的目的端口（收侧过滤用同一个常数）

    wire        eth_gmii_clk;
    wire [31:0] eth_ddr_base;
    wire        eth_commit;
    wire        pl_copy_hold;
    wire [319:0] eth_lm_bus;
    wire        eth_lm_tog, eth_lm_hb;

    eth_udp_video_top #(
        .IMG_W(VIDEO_W), .IMG_H(VIDEO_H),
        .BASE_ADDR(DDR_BASE),
        .UDP_PORT(UDP_VIDEO_PORT),
        .BOARD_MAC(48'h00_11_22_33_44_55),
        .BOARD_IP({8'd192,8'd168,8'd1,8'd10}),
        .IDELAY_VALUE(15)
    ) u_eth (
        .rgmii_rxc(eth_rxc),
        .rst_n(eth_rst_n & mmcm_locked),
        .axi_clk(fclk0),
        .axi_rst_n(fclk0_rst_n),
        .idelay_clk(clk_200m),
        .copy_hold(pl_copy_hold),
        .rgmii_rx_ctl(eth_rx_ctl),
        .rgmii_rxd(eth_rxd),
        .rgmii_tx_clk(eth_tx_clk),
        .rgmii_tx_ctl(eth_tx_ctl),
        .rgmii_txd(eth_txd),
        .fb_wr_en(eth_wr_en),
        .fb_wr_addr(eth_wr_addr),
        .fb_wr_data(eth_wr_data),
        .frame_done(eth_frame_done),
        .link_active(eth_link),
        .eth_gmii_clk(eth_gmii_clk),
        .ddr_commit_base(eth_ddr_base),
        .ddr_commit_pulse(eth_commit),
        .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst),
        .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb),
        .m_axi_wlast(m_wlast), .m_axi_wvalid(m_wvalid),
        .m_axi_wready(m_wready),
        .m_axi_bvalid(m_bvalid), .m_axi_bready(m_bready),
        .stat_frames(eth_frames), .stat_pkts(eth_pkts),
        .stat_bytes(eth_bytes), .stat_bad(eth_bad),
        .lm_bus(eth_lm_bus), .lm_bus_tog(eth_lm_tog), .lm_hb(eth_lm_hb),
        .gapclr_sel(gpio_o[26])          // 测量前把帧间隔统计归零（见 link_monitor 尾部）
    );

    // ---- v7.6 (P0-A)：把健康快照再跨一份到 fclk0（100 MHz）给 PS 读 ----
    // 读法：先用**已经存在**的 GPIO_0（输出）把 lane 号写到 gpio_o[31:27]，
    // 再从新加的 GPIO_1（输入）读那一条 32bit。lane 定义见 link_monitor 尾部。
    //   lane 31 → {30'd0, hb_slow, hb_gone}：bit0=源时钟没有，bit1=源时钟被拉慢
    //   （板级实测拔线时 RXC≈2.5 MHz ⇒ 只有 bit1 会亮），
    //   其它越界的 lane → 32'hDEAD_BEEF，好让脚本一眼看出自己写错了号。
    wire [319:0] lm_axi;
    wire         lm_clk_gone, lm_clk_slow;
    snap_cross #(.W(320), .DST_HZ(100_000_000), .HB_TO_MS(200)) u_lm_axi (
        .dst_clk(fclk0), .dst_rst_n(fclk0_rst_n),
        .bus(eth_lm_bus), .bus_tog(eth_lm_tog), .hb_tog(eth_lm_hb),
        .bus_q(lm_axi), .hb_gone(lm_clk_gone), .hb_slow(lm_clk_slow)
    );
    wire [4:0] lm_lane = gpio_o[31:27];
    reg  [31:0] lm_rd;
    // 片源仲裁的可观测状态（来自 pl_video_top，axi_clk=fclk0 域电平）：
    //   bit0=eth_tb_ok bit1=eth_live bit2=owner_eth，bit[5:3] 恒 0
    //   （#26 一度把像素域的 mode / ps_src_seen 也打拍放进来，代价是 cdc.rpt 多一条 Critical，
    //    已撤；那两位属于"看图卡有没有上屏"的眼睛判据，不需要机器读回）
    // 有了 lane30，"停流后 owner_eth 是否在几十毫秒内从 1 变 0"就是**可机器判定**的，
    // 不必等任何人看屏幕（判据：`src/host/health_read.mjs` 的 --json 输出）。
    // ⚠ 位宽必须与 `pl_video_top.dbg_src` **一模一样**（r54 起是 16 bit：bit[6:5] = 模式，
    //   bit[10:8] = V8-7 的 why_ps）。这里以前写过 [5:0] ⇒ 综合只给一条 `Synth 8-689` 警告
    //   就把模式的高位**静默丢掉**，lane30 的 mode 于是永远只能读成 0/1：
    //   锁图卡(10) 读起来像自动(00)、锁PS(11) 读起来像锁ETH(01)。2026-09-24 才发现 —— ISSUES #57。
    //   这一类"名字连对、宽度被吞"现在由门禁第 14 项的**位宽判据**当场拦（`build/check_ports.py`，
    //   它的反例之一改的就是这一根线）。
    wire [15:0] dbg_src;
    wire [31:0] dbg_zoom;              // V8-8 lane23：像素域在用的缩放状态（pl_video_top 里已跨好）
    wire [6*32-1:0] dbg_lat;             // V8-6/V8-5：lane25..29 与 lane24
    //   lane N(25..29) = dbg_lat[(N-25)*32 +: 32]；lane24 = dbg_lat[5*32 +: 32] = q_ms
    //   lane24 的位序 {14'd0, pair_ok, 本轮 sticky, ms[15:0]} —— 屏上 Latency 那一格的机器对照
    // 指到 lane25 就把这一组五个字**同时**抄进快照（#59：逐 lane 各读各的会读到不同轮，
    // 于是板级 11 组读数里 4 组破坏了恒等式 tot ≥ c1 + c2）。
    // 读这一组的顺序必须是 25→26→27→28→29，因为 25 既是"轮次/钳位位"也是武装位；
    // `health_read.mjs` 的 want 列表就是这个顺序，改那里的时候记得一起看。
    // 域：gpio_o 由 axi 写更新，frame_latency 也在 axi 域 ⇒ 这不是跨域信号。
    wire          lat_arm = (lm_lane == 5'd25);
    always @(*) begin
        if      (lm_lane == 5'd31)     lm_rd = {30'd0, lm_clk_slow, lm_clk_gone};
        else if (lm_lane == 5'd30)     lm_rd = {16'd0, dbg_src};   // [10:8]=why_ps（V8-7）
        else if (lm_lane == 5'd24)     lm_rd = dbg_lat[5*32 +: 32];   // 与 q_tot 同一轮的 ms
        else if (lm_lane == 5'd23)     lm_rd = dbg_zoom;              // V8-8：像素域在用的缩放状态
        else if (lm_lane >= 5'd25 && lm_lane <= 5'd29)
                                       lm_rd = dbg_lat[(lm_lane-25)*32 +: 32];
        else if (lm_lane > 5'd9)       lm_rd = 32'hDEAD_BEEF;
        else                           lm_rd = lm_axi[lm_lane*32 +: 32];
    end
    assign gpio1_i = lm_rd;

    // 片源仲裁的两个输入，都取自已经 u_lm_axi 同步进 fclk0 的现成信号 ⇒ 顶层不新增跨域，
    // 也**不在这里做相与**：判据的组合归 src_arb 管（那里才台架验得到，见 tb_v796_src_arb 的 E 段）。
    //   · eth_live = 快照 lane7.bit3 = (stall_ms < 200)，"最近真的收到过完整帧"；
    //   · eth_tb_ok  = 量它的源时基仍准。板级实测（今晚就撞了）：断链时 RTL8211 不停 RXC
    //     而是拉到 ~2.5 MHz ⇒ stall_ms 慢约 48 倍地爬，单看那一位会永远判"活着"，
    //     于是仲裁死死占住 ETH、SD 再也接不回画面（屏幕上同时表现为 STALL=9999 ——
    //     那是 OSD 钉住的显示值，不是 9999 ms）。hb_slow 专门看的就是这种"心跳还在但变慢"。
    wire eth_live   = lm_axi[7*32 + 3];
    wire eth_tb_ok  = !(lm_clk_slow || lm_clk_gone);

    pl_video_top #(.IMG_W(VIDEO_W), .IMG_H(VIDEO_H), .PANE_W(PANE_W), .BASE_ADDR(DDR_BASE),
                   .PS_BASE_ADDR(PS_DDR_BASE)) u_pl (
        .sys_clk(sys_clk), .sys_rst_n(1'b1),
        .axi_clk(fclk0), .axi_rst_n(fclk0_rst_n),
        .effect_en(gpio_o[4:0]), .stage_sel(gpio_cfg1_o[8:0]), .threshold(gpio_o[15:8]), .src_sel(gpio_o[16]),
        // V8-8 手动缩放：**同一个字**的高位（PS 侧 CFG_DATA0 = 0x41220000）：
        //   [28:26] 档号、[29] 手动旗标。异步性一致 ⇒ 一并交给 effect_ctrl 那条 sel 链。
        //   ⚠ 别写成 gpio_cfg2_o：那是 PS 侧 +0x08 的 gamma 窗口（命名差一位是这里的坑）。
        .zoom_sel_async(gpio_cfg1_o[28:26]), .zoom_manual_async(gpio_cfg1_o[29]),
        .gamma_ctl(gpio_cfg2_o),        // axi_gpio_2 通道 2（+0x08）：gamma 表的 idx/data/wr/en
        // V7.7：ZOOM0/ZOOM1 不再是死命令。之前这里硬绑 1'b1，串口命令与 GPIO bit17 全无效
        // （main.c 自己就注明"当前 RTL 常开，bit17 仅预留"）。
        // 注意默认值：set_src.tcl 现在写 0x0003_0000（bit16+bit17），保持"上电即呼吸缩放"的旧观感。
        .zoom_en(gpio_o[17]),
        .ps_publish(gpio_o[18]),        // 每翻转一次 = PS 请求把 DDR 里那一帧搬上屏一次
        .key1_n(key1_n), .key2_n(key2_n), .led(led),
        .dbg_src(dbg_src), .dbg_lat(dbg_lat), .dbg_zoom(dbg_zoom), .lat_arm(lat_arm),
        .tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p), .tmds_data_n(tmds_data_n),
        .m_axi_araddr(m_araddr), .m_axi_arid(m_arid), .m_axi_arlen(m_arlen8),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst),
        .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rdata(m_rdata), .m_axi_rid(m_rid), .m_axi_rresp(m_rresp),
        .m_axi_rlast(m_rlast), .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),
        .eth_wr_clk(eth_gmii_clk),
        .eth_wr_en(eth_wr_en),
        .eth_wr_addr(eth_wr_addr),
        .eth_wr_data(eth_wr_data),
        .eth_link(eth_link),
        .eth_live(eth_live),
        .eth_tb_ok(eth_tb_ok),
        .eth_frame(eth_frame_done),
        .eth_ddr_base(eth_ddr_base),
        .eth_commit(eth_commit),
        .eth_pkts(eth_pkts[15:0]),
        .eth_bad(eth_bad[15:0]),
        // lm_bus / lm_bus_tog / lm_hb 三个口跟着 V8-5 的 OSD 改版一起撤掉了：
        // 像素域那一路快照从此没有消费者（DROP/STALL 两格撤下屏）。
        // 这三个数仍然从 axi 域那条 snap_cross（上面 lane 读回口用的那一条）出去，
        // `health_read.mjs` 一字未改照样读得到。
        .status(status),
        .copy_hold(pl_copy_hold)
    );
endmodule
