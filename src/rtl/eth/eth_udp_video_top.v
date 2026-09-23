`timescale 1ns/1ps
// ETH UDP video top — ghosting-fix v5
// DDR ping-pong + burst saver; commit pulse with completed base.
module eth_udp_video_top #(
    parameter IMG_W      = 512,
    parameter IMG_H      = 300,
    parameter BASE_ADDR  = 32'h1000_0000,
    parameter [15:0] UDP_PORT = 16'd5001,
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_55,
    parameter [31:0] BOARD_IP  = {8'd192,8'd168,8'd1,8'd10},
    parameter IDELAY_VALUE = 15
)(
    input  wire        rgmii_rxc,
    input  wire        rst_n,
    input  wire        axi_clk,
    input  wire        axi_rst_n,
    input  wire        idelay_clk,
    input  wire        copy_hold,

    input  wire        rgmii_rx_ctl,
    input  wire [3:0]  rgmii_rxd,
    output wire        rgmii_tx_clk,
    output wire        rgmii_tx_ctl,
    output wire [3:0]  rgmii_txd,

    output wire        fb_wr_en,
    output wire [18:0] fb_wr_addr,
    output wire [15:0] fb_wr_data,
    output wire        frame_done,
    output wire        link_active,
    // "最近真的有帧"（stall_ms < LIVE_MS，eth_rxc 域电平）。
    // 与 link_active 的区别就是片源仲裁需要的那一点：link_active 是"自配置以来收过任何一个包"
    // （ARP 就够触发、拔线也不回 0），link_live 会在断流 ~200 ms 后自己落回去。
    output wire        link_live,
    output wire        eth_gmii_clk,

    output wire [31:0] ddr_commit_base,
    output wire        ddr_commit_pulse,

    output wire [31:0] m_axi_awaddr,
    output wire [7:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire        m_axi_awvalid,
    input  wire        m_axi_awready,
    output wire [63:0] m_axi_wdata,
    output wire [7:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output wire        m_axi_wvalid,
    input  wire        m_axi_wready,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,

    output wire [31:0] stat_frames,
    output wire [31:0] stat_pkts,
    output wire [31:0] stat_bytes,
    output wire [31:0] stat_bad,

    // v7.6 (P0-A)：链路健康快照总线 + 两个跳变信号，全部在 eth_rxc 域。
    // 跨域（像素域 OSD / PS 侧 GPIO）由消费方用 snap_cross 完成。
    output wire [319:0] lm_bus,
    output wire         lm_bus_tog,
    output wire         lm_hb,
    // v7.6c：帧间隔统计清零的选择位（来自 PS 侧 GPIO，fclk0 域的电平）。gap_max 是
    // 终身保持的，一次长空闲就会污染它（还会因回卷读小），所以测量前要有归零入口。
    input  wire         gapclr_sel
);
    localparam [31:0] BANK0 = BASE_ADDR;
    localparam [31:0] BANK1 = BASE_ADDR + 32'h0008_0000;

    wire gmii_rx_clk, gmii_rx_dv, gmii_tx_clk, gmii_tx_en;
    wire [7:0] gmii_rxd, gmii_txd;

    gmii_to_rgmii #(.IDELAY_VALUE(IDELAY_VALUE)) u_rgmii (
        .idelay_clk(idelay_clk),
        .gmii_rx_clk(gmii_rx_clk), .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd),
        .gmii_tx_clk(gmii_tx_clk), .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
        .rgmii_rxc(rgmii_rxc), .rgmii_rx_ctl(rgmii_rx_ctl), .rgmii_rxd(rgmii_rxd),
        .rgmii_txc(rgmii_tx_clk), .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txd(rgmii_txd)
    );

    wire        arp_rx_done, arp_rx_type, arp_tx_en, arp_tx_done;
    wire [47:0] src_mac;
    wire [31:0] src_ip;
    wire        arp_gmii_tx_en;
    wire [7:0]  arp_gmii_txd;

    wire        icmp_rec_pkt_done, icmp_rec_en;
    wire [7:0]  icmp_rec_data;
    wire [15:0] icmp_rec_byte_num;
    wire        icmp_tx_done, icmp_tx_req;
    wire        icmp_gmii_tx_en;
    wire [7:0]  icmp_gmii_txd, icmp_tx_data;
    reg  [15:0] icmp_tx_byte_num;
    reg  [5:0]  icmp_dly;
    reg         icmp_tx_start_en;
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) begin
            icmp_dly <= 0; icmp_tx_start_en <= 0; icmp_tx_byte_num <= 0;
        end else begin
            icmp_tx_start_en <= 0;
            if (icmp_rec_pkt_done) begin
                icmp_dly <= 6'd20;
                icmp_tx_byte_num <= icmp_rec_byte_num;
            end else if (icmp_dly != 0) begin
                icmp_dly <= icmp_dly - 1'b1;
                if (icmp_dly == 6'd1) icmp_tx_start_en <= 1'b1;
            end
        end
    end

    wire        udp_gmii_tx_en, udp_tx_done, udp_tx_req;
    wire [7:0]  udp_gmii_txd, udp_tx_data;
    wire [7:0]  crc_d8;   // V7.9.6：crc32_d8 的输入 = 发送线上正在出的字节（原来在 udp.v 内部）
    wire [7:0]  fifo_tx_data;
    wire        fifo_tx_req, fifo_rec_en;
    wire [7:0]  fifo_rec_data;

    wire [7:0] icmp_fifo_q;
    sync_fifo #(.DATA_W(8), .ADDR_W(11)) u_icmp_fifo (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .wr_en(icmp_rec_en), .wr_data(icmp_rec_data),
        .full(), .empty(), .level(),
        .rd_en(icmp_tx_req), .rd_data(icmp_fifo_q)
    );

    arp #(
        .BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP),
        .DES_MAC(48'hff_ff_ff_ff_ff_ff), .DES_IP({8'd192,8'd168,8'd1,8'd102})
    ) u_arp (
        .rst_n(rst_n),
        .gmii_rx_clk(gmii_rx_clk), .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd),
        .gmii_tx_clk(gmii_tx_clk), .gmii_tx_en(arp_gmii_tx_en), .gmii_txd(arp_gmii_txd),
        .arp_rx_done(arp_rx_done), .arp_rx_type(arp_rx_type),
        .src_mac(src_mac), .src_ip(src_ip),
        .arp_tx_en(arp_tx_en), .arp_tx_type(1'b1),
        .des_mac(src_mac), .des_ip(src_ip),
        .tx_done(arp_tx_done)
    );

    icmp #(
        .BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)
    ) u_icmp (
        .rst_n(rst_n),
        .gmii_rx_clk(gmii_rx_clk), .gmii_rx_dv(gmii_rx_dv), .gmii_rxd(gmii_rxd),
        .gmii_tx_clk(gmii_tx_clk), .gmii_tx_en(icmp_gmii_tx_en), .gmii_txd(icmp_gmii_txd),
        .rec_pkt_done(icmp_rec_pkt_done), .rec_en(icmp_rec_en), .rec_data(icmp_rec_data),
        .rec_byte_num(icmp_rec_byte_num),
        .tx_start_en(icmp_tx_start_en), .tx_data(icmp_fifo_q),
        .tx_byte_num(icmp_tx_byte_num),
        .des_mac(src_mac), .des_ip(src_ip),
        .tx_done(icmp_tx_done), .tx_req(icmp_tx_req)
    );

    // ---- V7.9.6（ISSUES #38）：收侧换成自研那一对，发侧只留厂商 udp_tx ----
    // 原来例化的是厂商 `udp` 包装层（udp_rx + udp_tx 一起进来）。udp_rx 不看帧长、也没有错误
    // 标志可看（RGMII 只有 4 数据 + 1 控制，RX_CTL 在 rgmii_rx.v 里只当 gmii_rx_dv 用，
    // **板上根本没有 RX_ER 这根线**）⇒ 下面 frame_reasm 的 p_good 只能硬接 1 ⇒ 遥测/OSD 里的
    // "坏包"是构造性为 0 的死数字。现在错误源由 gmii_rx_mac 逐字节算 FCS-32 自己造出来。
    // 发侧维持今天的状态（`tx_start_en` 恒 0，UDP 发送在 Z7 上是接着但没人启动），
    // 只是不再连带把 udp_rx 拉回来。判据：sim/tb_v795_rx_chain.v（C1..C5）。
    wire        crc_en, crc_clr;
    wire [31:0] crc_data, crc_next;
    assign crc_d8 = udp_gmii_txd;

    udp_tx #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)) u_udp_tx (
        .clk        (gmii_tx_clk),
        .rst_n      (rst_n),
        .tx_start_en(1'b0),                       // 与今天一致：Z7 不发 UDP
        .tx_data    (8'd0),
        .tx_byte_num(16'd0),
        .des_mac    (src_mac),
        .des_ip     (src_ip),
        .crc_data   (crc_data),
        .crc_next   (crc_next[31:24]),
        .tx_done    (udp_tx_done),
        .tx_req     (udp_tx_req),
        .gmii_tx_en (udp_gmii_tx_en),
        .gmii_txd   (udp_gmii_txd),
        .crc_en     (crc_en),
        .crc_clr    (crc_clr)
    );
    crc32_d8 u_crc_tx (
        .clk(gmii_tx_clk), .rst_n(rst_n), .data(crc_d8),
        .crc_en(crc_en), .crc_clr(crc_clr), .crc_data(crc_data), .crc_next(crc_next));

    wire [7:0] rx_m_data;
    wire       rx_m_valid, rx_m_sof, rx_m_eof, rx_m_good, rx_m_bad;
    gmii_rx_mac u_rx_mac (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .gmii_rxd(gmii_rxd), .gmii_rx_dv(gmii_rx_dv),
        .gmii_rx_er(1'b0),          // RGMII 没有 RX_ER 通道；真正的判定在 FCS 那一级
        .m_data(rx_m_data), .m_valid(rx_m_valid), .m_sof(rx_m_sof),
        .m_eof(rx_m_eof), .m_good(rx_m_good), .m_bad(rx_m_bad)
    );
    wire [7:0]  p_data;
    wire        p_valid, p_sof, p_eof, p_good;
    wire [15:0] p_pay_len;
    wire        st_drop_bad, st_drop_filt, st_udp_ok;
    udp_rx_parser #(.UDP_PORT(UDP_PORT)) u_rx_par (        // 目的端口过滤：P0-C 最后那条债
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .s_data(rx_m_data), .s_valid(rx_m_valid), .s_sof(rx_m_sof),
        .s_eof(rx_m_eof), .s_good(rx_m_good), .s_bad(rx_m_bad),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .pay_len(p_pay_len),
        .stat_drop_bad(st_drop_bad), .stat_drop_filt(st_drop_filt), .stat_udp_ok(st_udp_ok)
    );

    eth_ctrl u_ctrl (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .arp_rx_done(arp_rx_done), .arp_rx_type(arp_rx_type),
        .arp_tx_en(arp_tx_en), .arp_tx_type(), .arp_tx_done(arp_tx_done),
        .arp_gmii_tx_en(arp_gmii_tx_en), .arp_gmii_txd(arp_gmii_txd),
        .icmp_tx_start_en(icmp_tx_start_en), .icmp_tx_done(icmp_tx_done),
        .icmp_gmii_tx_en(icmp_gmii_tx_en), .icmp_gmii_txd(icmp_gmii_txd),
        .icmp_rec_en(icmp_rec_en), .icmp_rec_data(icmp_rec_data),
        .icmp_tx_req(icmp_tx_req), .icmp_tx_data(),
        .udp_tx_start_en(1'b0), .udp_tx_done(udp_tx_done),
        .udp_gmii_tx_en(udp_gmii_tx_en), .udp_gmii_txd(udp_gmii_txd),
        .udp_rec_data(p_data), .udp_rec_en(p_valid),   // 这条 rec 转发路径本设计无人消费；接真字节而不是硬 0
        .udp_tx_req(udp_tx_req), .udp_tx_data(),
        .tx_data(fifo_tx_data), .tx_req(fifo_tx_req),
        .rec_en(fifo_rec_en), .rec_data(fifo_rec_data),
        .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd)
    );

    wire [31:0] s_frames, s_pkts, s_bytes, s_badc, s_oob;
    // V7.9.6：原来这里要用"上一个字节没到、这一字节到了"自己凑一个 sof，
    // 因为厂商 udp_rx 不给边界；parser 直接给 p_sof/p_eof，那段推导随之删掉。

    wire reasm_flush;
    wire reasm_ferr, reasm_fabort;
    wire [15:0] reasm_rows_miss;
    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_reasm (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid),
        .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),   // ← 这一位从此是**真值**（原来是 1'b1）
        .wr_en(fb_wr_en), .wr_addr(fb_wr_addr), .wr_data(fb_wr_data),
        .flush(reasm_flush),
        .frame_done(frame_done), .frame_err(reasm_ferr),
        .frame_abort(reasm_fabort), .rows_missed(reasm_rows_miss),
        .stat_frames(s_frames), .stat_pkts(s_pkts),
        .stat_bytes(s_bytes), .stat_bad(s_badc), .stat_oob_off(s_oob)
    );

    wire [35:0] fifo_dout;
    wire fifo_empty, fifo_full;
    reg  fifo_rd;
    reg  [35:0] cdc_d1;
    reg         cdc_d1_v;
    reg  sav_en, sav_flush;
    reg [18:0] sav_a;
    reg [15:0] sav_d;
    reg  flush_pend;
    wire sv_full;      // v6.2: 打包器 FIFO 满 ⇒ 反压 CDC 读（取出来丢掉等于白读）

    // v6.1: 一个 1392B 的包在 125MHz 下是**连续线速**进来的（上位机限速只能拉开
    // 包间隔），每包 698 个 16bit 写。原来读侧限成「每 3 个 axi 周期取 1 条」
    // = 66 MB/s < 125 MB/s，单包就能把 512 深的 CDC 灌满 → 稳定丢 ~46% 的字，
    // 表现为板上「每隔一个 16bit 空洞」的黑纹，且与上位机速率无关。
    // 现在 1 条/周期（200 MB/s），并且 flush 标记永远让路给真实数据写。
    wire cdc_wr = (fb_wr_en || reasm_flush || flush_pend) && !fifo_full;
    wire [35:0] cdc_data = fb_wr_en ? {1'b0, fb_wr_addr, fb_wr_data}
                                    : {1'b1, 19'd0, 16'd0};

    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) flush_pend <= 1'b0;
        else if (reasm_flush && fb_wr_en && !fifo_full) flush_pend <= 1'b1;
        else if (flush_pend && !fb_wr_en && !fifo_full) flush_pend <= 1'b0;
    end

    // v7.6 (P0-A)：把「这一拍的 CDC 写被 fifo_full 挡住了」变成可读数——这是上板
    // 唯一真实的丢数据通道（p_good 硬接 1 ⇒ frame_reasm 的坏包统计是死的）。
    // gapclr_sel 是 fclk0 域的电平，进本域必须先 3FF（工程里 src_sel/allow_copy 同一套路）。
    // 它是准静态控制位、不是脉冲，所以同步后直接当电平用，不需要握手。
    (* ASYNC_REG = "TRUE" *) reg gc0, gc1, gc2;
    always @(posedge gmii_rx_clk or negedge rst_n) begin
        if (!rst_n) {gc2, gc1, gc0} <= 3'b0;
        else        {gc2, gc1, gc0} <= {gc1, gc0, gapclr_sel};
    end

    wire cdc_wr_req = fb_wr_en || reasm_flush || flush_pend;
    link_monitor #(
        .CLK_HZ(125_000_000), .LIVE_MS(16'd200)
    ) u_lm (
        .clk(gmii_rx_clk), .rst_n(rst_n),
        .cdc_wr_req(cdc_wr_req), .cdc_full(fifo_full),
        .frame_done(frame_done), .frame_abort(reasm_fabort),
        .frame_err(reasm_ferr), .rows_missed(reasm_rows_miss),
        .in_pkts(s_pkts), .in_bytes(s_bytes), .gapclr(gc2),
        .lm_bus(lm_bus), .lm_bus_tog(lm_bus_tog), .lm_hb(lm_hb), .lm_live(link_live)
    );

    // v6.2: 缓冲主力——BRAM 实现的 CDC（dc_fifo 带 ram_style="block"）。
    // 8192 条 = 4096 个 64bit 字 = 16 KB，足以吸收「显示拷贝独占 HP0 一整个
    // V-blank」期间到达的入包数据（15 MBps × 672 µs ≈ 1260 字）。
    dc_fifo #(.DATA_W(36), .ADDR_W(13)) u_cdc (
        .wr_clk(gmii_rx_clk), .wr_rst_n(rst_n),
        .wr_en(cdc_wr),
        .wr_data(cdc_data),
        .wr_full(fifo_full),
        .rd_clk(axi_clk), .rd_rst_n(axi_rst_n),
        .rd_en(fifo_rd), .rd_data(fifo_dout), .rd_empty(fifo_empty)
    );

    always @(posedge axi_clk or negedge axi_rst_n) begin
        if (!axi_rst_n) begin
            fifo_rd<=0; cdc_d1<=0; cdc_d1_v<=0;
            sav_en<=0; sav_flush<=0; sav_a<=0; sav_d<=0;
        end else begin
            fifo_rd  <= !fifo_empty && !sv_full;
            cdc_d1   <= fifo_dout;
            cdc_d1_v <= fifo_rd;
            sav_en    <= cdc_d1_v && !cdc_d1[35];
            sav_flush <= cdc_d1_v &&  cdc_d1[35];
            if (cdc_d1_v) begin
                sav_a <= cdc_d1[34:16];
                sav_d <= cdc_d1[15:0];
            end
        end
    end

    wire       saver_idle;
    wire [31:0] sav_base;
    wire       pack_flush;

    // v6.4 的「帧尾 4 字节偶发丢失」修在这里：换页必须等本帧数据全部穿过 CDC。
    // 这段 glue 从本文件抽成独立模块，是为了让 tb_v6_pingpong / tb_v6_tail_bank
    // 例化**上板的实现**而不是 TB 里的手抄副本。
    ddr_bank_commit #(
        .BANK0(BANK0), .BANK1(BANK1), .TAIL_GUARD(1'b1)
    ) u_commit (
        .gmii_clk      (gmii_rx_clk),
        .axi_clk       (axi_clk),
        .rst_n         (rst_n),
        .axi_rst_n     (axi_rst_n),
        .frame_done    (frame_done),
        .saver_idle    (saver_idle),
        .sav_base      (sav_base),
        .pack_flush    (pack_flush),
        .cdc_empty     (fifo_empty),
        .cdc_rd        (fifo_rd),
        .cdc_d1_v      (cdc_d1_v),
        .sav_en        (sav_en),
        .sav_flush     (sav_flush),
        .completed_base(ddr_commit_base),
        .commit_pulse  (ddr_commit_pulse),
        .switch_req    (),
        .force_flush   ()
    );

    // v5.0: use saver64 so idle/commit/frame_ready can complete (burst hung → red).
    // v6.2: 打包器满时停止从 CDC 取数（反压），否则取出来就丢，等于白读。
    axi_frame_saver64 #(.BASE_ADDR(BANK0)) u_saver (
        .clk(axi_clk), .rst_n(axi_rst_n), .enable(1'b1),
        .base_addr(sav_base),
        .wr_en(sav_en), .wr_addr(sav_a), .wr_data(sav_d),
        .flush(pack_flush),
        .fifo_full(sv_full), .idle(saver_idle), .busy(),
        .m_axi_awaddr(m_axi_awaddr), .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize), .m_axi_awburst(m_axi_awburst),
        .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata), .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast), .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bvalid(m_axi_bvalid), .m_axi_bready(m_axi_bready)
    );

    assign stat_frames = s_frames;
    assign stat_pkts   = s_pkts;
    assign stat_bytes  = s_bytes;
    assign stat_bad    = s_badc;
    assign link_active = |s_pkts[15:0];
    assign eth_gmii_clk = gmii_rx_clk;
endmodule
