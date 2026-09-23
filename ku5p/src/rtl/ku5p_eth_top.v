`timescale 1ns/1ps
// RK-XCKU5P-F 上的以太网视频入口 —— 本工程 Zynq 版协议栈的 UltraScale+ 移植验证顶层。
//
// 这块板子没有 HDMI 输出（原理图 21 页里 HDMI/TMDS/LCD 零命中，显示要另配 FH1159 子卡），
// 所以这里证明的不是"能显示"，而是那句更重要的话：
//   **同一套自研以太网栈（GMII MAC / ARP / ICMP / UDP / offset 拼帧 / 链路健康计数）
//    不依赖任何厂商 IP，就能在 UltraScale+ 上跑起来。**
// 判据形式：综合 + 实现收敛 + 资源数字；明天上板再补 ping 通与收流统计。
//
// 与 Zynq 版 `src/rtl/eth/eth_udp_video_top.v` 的三处实质差别（其余照搬）：
//   1) RGMII IO 换层：7 系列用 IDELAYE2 + IDDR，UltraScale+ 用 BUFG + BUFIO + IDDRE1 / ODDRE1
//      （`ku5p/src/rtl/rgmii_*.v`，取自厂商例程并注明出处）。IDELAY 那一级先不补，
//      理由见 ku5p/README.md 的未决问题。
//   2) **整个入口是单时钟域**：Zynq 版必须跨到 50 MHz 像素域才能写显示缓存，
//      这里没有显示消费者，所以 `dc_fifo` / `axi_frame_saver*` / DDR 乒乓全部不需要，
//      拼帧结果直接打进 BRAM。少掉的正是当初最难对的那部分逻辑。
//   3) 没有 PS，也就没有 AXI GPIO / HP0：状态改由 LED 表示（见文件末尾的 LED 表）。
module ku5p_eth_top #(
    parameter [15:0] IMG_W     = 16'd512,
    parameter [15:0] IMG_H     = 16'd300,
    parameter [15:0] UDP_PORT  = 16'd5001,
    parameter [47:0] BOARD_MAC = 48'h00_11_22_33_44_66,   // 与 Zynq 板必须不同（同网段）
    parameter [31:0] BOARD_IP  = {8'd192,8'd168,8'd1,8'd11}
)(
    input  wire        eth_rxc,     // PHY 恢复时钟 125 MHz，K22（GC 脚）
    input  wire        eth_rx_ctl,
    input  wire [3:0]  eth_rxd,
    output wire        eth_txc,
    output wire        eth_tx_ctl,
    output wire [3:0]  eth_txd,

    input  wire        sys_rst_n,   // 板载按键 K9，低有效
    output wire [3:0]  led    // 这块板只有 4 个 LED（bank86/3.3 V）
);
    // ---- 上电复位拉伸：按键有硬件 100 nF 滤波，但仍要把异步释放变成同步释放 ----
    wire rst_n;
    reg [15:0] por = 16'h0;
    always @(posedge eth_rxc or negedge sys_rst_n) begin
        if (!sys_rst_n) por <= 16'h0;
        else if (~&por)   por <= por + 16'd1;
    end
    assign rst_n = &por;

    // ---- RGMII ↔ GMII ----
    wire        g_clk, g_rx_dv, g_tx_clk, g_tx_en;
    wire [7:0]  g_rxd, g_txd;

    gmii_to_rgmii u_phy (
        .gmii_rx_clk(g_clk), .gmii_rx_dv(g_rx_dv), .gmii_rxd(g_rxd),
        .gmii_tx_clk(g_tx_clk), .gmii_tx_en(g_tx_en), .gmii_txd(g_txd),
        .rgmii_rxc(eth_rxc), .rgmii_rx_ctl(eth_rx_ctl), .rgmii_rxd(eth_rxd),
        .rgmii_txc(eth_txc), .rgmii_tx_ctl(eth_tx_ctl), .rgmii_txd(eth_txd)
    );

    // ---- ARP / ICMP / UDP：这一段与 Zynq 版逐行同构（含 ICMP 回包的那个 20 拍延时），
    //      差别只在"谁有权把字节送上 GMII"改由自研的 ku5p_tx_arb 决定（理由见该文件头）。
    wire        arp_rx_done, arp_rx_type, arp_tx_done, arp_gmii_tx_en;
    wire [47:0] src_mac;
    wire [31:0] src_ip;
    wire [7:0]  arp_gmii_txd;
    wire        arp_grant, icmp_grant, udp_grant;

    // 收到 ARP **请求**（type 0）= 想发 ARP 应答。打一拍再送仲裁器，避免把
    // arp_rx_done/arp_rx_type 的组合逻辑塞进请求路径。
    reg arp_rqs;
    always @(posedge g_clk or negedge rst_n) begin
        if (!rst_n) arp_rqs <= 1'b0;
        else        arp_rqs <= arp_rx_done && (arp_rx_type == 1'b0);
    end

    wire        icmp_rec_pkt_done, icmp_rec_en, icmp_tx_done, icmp_tx_req, icmp_gmii_tx_en;
    wire [7:0]  icmp_rec_data, icmp_gmii_txd, icmp_fifo_q;
    wire [15:0] icmp_rec_byte_num;
    reg  [15:0] icmp_tx_byte_num;
    reg  [5:0]  icmp_dly;
    reg         icmp_rqs;            // 向仲裁器"请求"回 ICMP 包（不是直接 start）
    always @(posedge g_clk or negedge rst_n) begin
        if (!rst_n) begin
            icmp_dly <= 0; icmp_rqs <= 0; icmp_tx_byte_num <= 0;
        end else begin
            icmp_rqs <= 0;
            if (icmp_rec_pkt_done) begin
                icmp_dly <= 6'd20;
                icmp_tx_byte_num <= icmp_rec_byte_num;
            end else if (icmp_dly != 0) begin
                icmp_dly <= icmp_dly - 1'b1;
                if (icmp_dly == 6'd1) icmp_rqs <= 1'b1;
            end
        end
    end

    wire        udp_gmii_tx_en, udp_tx_done, udp_tx_req;
    wire [7:0]  udp_gmii_txd;

    // 遥测的取数口必须在使用之前声明 —— 否则 Verilog 会先按"隐式网"（1 bit）把
    // u_udp 的 .tx_data/.tx_byte_num 接上，后面的显式声明就成了重复声明。
    wire [7:0]  tlm_data;
    wire [15:0] tlm_len;
    wire        tlm_rqs;
    // 门 = ARP 学到过对端：厂商 udp_tx 在 des_mac==0 时会拿上一次的 eth_head 继续发，
    // 那等于往一个随机 MAC 发包，所以这一位不是"省电"而是"必须"。
    wire        peer_known = (src_ip != 32'd0) && (src_mac != 48'd0);

    sync_fifo #(.DATA_W(8), .ADDR_W(11)) u_icmp_fifo (
        .clk(g_clk), .rst_n(rst_n),
        .wr_en(icmp_rec_en), .wr_data(icmp_rec_data),
        .full(), .empty(), .level(),
        .rd_en(icmp_tx_req), .rd_data(icmp_fifo_q)
    );

    arp #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP),
          .DES_MAC(48'hff_ff_ff_ff_ff_ff), .DES_IP(32'h0)) u_arp (
        .rst_n(rst_n),
        .gmii_rx_clk(g_clk), .gmii_rx_dv(g_rx_dv), .gmii_rxd(g_rxd),
        .gmii_tx_clk(g_tx_clk), .gmii_tx_en(arp_gmii_tx_en), .gmii_txd(arp_gmii_txd),
        .arp_rx_done(arp_rx_done), .arp_rx_type(arp_rx_type),
        .src_mac(src_mac), .src_ip(src_ip),
        .arp_tx_en(arp_grant), .arp_tx_type(1'b1),
        .des_mac(src_mac), .des_ip(src_ip), .tx_done(arp_tx_done)
    );

    icmp #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)) u_icmp (
        .rst_n(rst_n),
        .gmii_rx_clk(g_clk), .gmii_rx_dv(g_rx_dv), .gmii_rxd(g_rxd),
        .gmii_tx_clk(g_tx_clk), .gmii_tx_en(icmp_gmii_tx_en), .gmii_txd(icmp_gmii_txd),
        .rec_pkt_done(icmp_rec_pkt_done), .rec_en(icmp_rec_en), .rec_data(icmp_rec_data),
        .rec_byte_num(icmp_rec_byte_num),
        .tx_start_en(icmp_grant), .tx_data(icmp_fifo_q),
        .tx_byte_num(icmp_tx_byte_num),
        .des_mac(src_mac), .des_ip(src_ip),
        .tx_done(icmp_tx_done), .tx_req(icmp_tx_req)
    );

    // ---- V7.9.6（ISSUES #38）：收侧换成自研那一对，发侧只留厂商 udp_tx ----
    // 原来这里例化的是厂商 `udp`，它把 udp_rx 和 udp_tx 一起拉进来：
    //   · udp_rx 不看帧长、也没有错误标志可看 ⇒ 顶层只能把 frame_reasm.p_good 硬接 1
    //     ⇒ 遥测包里的 `bad` 是**构造性为 0** 的死数字（#38 的原始症状）；
    //   · 而且 RGMII 收侧**根本没有 ER 这根线**（RX_CTL 只当 dv 用），所以"看 ER"这条路
    //     在这两块板上都不成立 —— 错误源必须自己造。现在由 gmii_rx_mac 逐字节算 FCS-32。
    // 发侧的 udp_tx 保留（IP/UDP/Ethernet 头与 FCS 都在它里面），但不再连带把 udp_rx 拉进来。
    wire        crc_en, crc_clr;
    wire [31:0] crc_data, crc_next;
    wire [7:0]  crc_d8;
    assign crc_d8 = udp_gmii_txd;

    udp_tx #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)) u_udp_tx (
        .clk        (g_tx_clk),
        .rst_n      (rst_n),
        .tx_start_en(udp_grant),
        .tx_data    (tlm_data),
        .tx_byte_num(tlm_len),
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
        .clk(g_tx_clk), .rst_n(rst_n), .data(crc_d8),
        .crc_en(crc_en), .crc_clr(crc_clr), .crc_data(crc_data), .crc_next(crc_next));

    // 收：GMII 字节流 → 去前导码 + FCS 判定 → IPv4/UDP 过滤 + 抽载荷
    wire [7:0] rx_m_data;
    wire       rx_m_valid, rx_m_sof, rx_m_eof, rx_m_good, rx_m_bad;
    gmii_rx_mac u_rx_mac (
        .clk(g_clk), .rst_n(rst_n),
        .gmii_rxd(g_rxd), .gmii_rx_dv(g_rx_dv),
        .gmii_rx_er(1'b0),          // RGMII 没有 RX_ER 通道，恒 0 是有意的（见 #38）；
                                    // 真正的错误判定在上面的 FCS 里
        .m_data(rx_m_data), .m_valid(rx_m_valid), .m_sof(rx_m_sof),
        .m_eof(rx_m_eof), .m_good(rx_m_good), .m_bad(rx_m_bad)
    );
    wire [7:0]  p_data;
    wire        p_valid, p_sof, p_eof, p_good;
    wire [15:0] p_pay_len;
    wire        st_drop_bad, st_drop_filt, st_udp_ok;
    udp_rx_parser #(.UDP_PORT(UDP_PORT)) u_rx_par (        // UDP_PORT=5001，与 Z7 同一口径
        .clk(g_clk), .rst_n(rst_n),
        .s_data(rx_m_data), .s_valid(rx_m_valid), .s_sof(rx_m_sof),
        .s_eof(rx_m_eof), .s_good(rx_m_good), .s_bad(rx_m_bad),
        .p_data(p_data), .p_valid(p_valid), .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .pay_len(p_pay_len),
        .stat_drop_bad(st_drop_bad), .stat_drop_filt(st_drop_filt), .stat_udp_ok(st_udp_ok)
    );

    // 厂商的 eth_ctrl 在这里被换成自研的 ku5p_tx_arb（见该文件头的理由），
    // 它同时管 ARP/ICMP/UDP 三路的 start 与 mux，例化放在统计寄存器之后。

    // ---- offset 拼帧（与 Zynq 版同一模块、同一判据） ----
    wire        fb_wr_en;
    wire [18:0] fb_wr_addr;   // 像素号
    wire [15:0] fb_wr_data;
    wire        reasm_flush, frame_done, reasm_ferr, reasm_fabort;
    wire [15:0] reasm_rows_miss;
    wire [31:0] s_frames, s_pkts, s_bytes, s_badc, s_oob;

    // p_good 现在是**真值**（gmii_rx_mac 的 FCS 判定经 udp_rx_parser 传下来），
    // 不再是原来那个 `.p_good(1'b1)` —— 于是 frame_reasm 的 stat_bad 活了，
    // 遥测包里的 `bad` 字段也从"构造性为 0"变成可当证据的数字（#38 结案的那一半）。
    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_reasm (
        .clk(g_clk), .rst_n(rst_n),
        .p_data(p_data), .p_valid(p_valid),
        .p_sof(p_sof), .p_eof(p_eof), .p_good(p_good),
        .wr_en(fb_wr_en), .wr_addr(fb_wr_addr), .wr_data(fb_wr_data),
        .flush(reasm_flush),
        .frame_done(frame_done), .frame_err(reasm_ferr),
        .frame_abort(reasm_fabort), .rows_missed(reasm_rows_miss),
        .stat_frames(s_frames), .stat_pkts(s_pkts),
        .stat_bytes(s_bytes), .stat_bad(s_badc), .stat_oob_off(s_oob)
    );

    // ---- 16→64 打包后写 BRAM：没有像素域消费者，所以这一级不再需要 dc_fifo ----
    //    打包本身单独成模块（src/rtl/video/fb_pack.v），因为它的错法很隐蔽：
    //    末尾 1~3 个像素不落盘 = 每行尾部黑一块；判据见 sim/tb_fb_pack.v。
    wire        pkr_we;
    wire [18:0] pkr_waddr;
    wire [63:0] pkr_wdata;
    fb_pack u_pack (
        .clk(g_clk), .rst_n(rst_n),
        .px_en(fb_wr_en), .px_addr(fb_wr_addr), .px_data(fb_wr_data),
        .flush(reasm_flush),
        .wr_en(pkr_we), .wr_addr(pkr_waddr), .wr_data(pkr_wdata)
    );

    // 读回侧的状态（声明必须在使用之前 —— 这次重构就差点把它们弄丢了）
    reg [18:0] rd_ptr;
    reg [31:0] rd_sum;
    reg [15:0] rd_xor, xor_at_frame;
    reg        data_alive;

    wire [15:0] fb_rd_data;
`ifdef FB_URAM_STYLE
    // 实验开关（`KU5P_FB=uram` 时才定义）：端口同形的 UltraRAM 版，用来**量**而不是用来猜。
    // 默认不定义 ⇒ 下面的实例与冻结的 r23 那一版完全同形。
    frame_buffer_uram #(.W(IMG_W), .H(IMG_H)) u_fb (
        .wr_clk(g_clk),
        .wr_en(pkr_we), .wr_addr(pkr_waddr), .wr_data(pkr_wdata),
        .rd_clk(g_clk), .rd_addr(rd_ptr[18:0]), .rd_data(fb_rd_data)
    );
`else
    frame_buffer_w64 #(.W(IMG_W), .H(IMG_H)) u_fb (
        .wr_clk(g_clk),
        .wr_en(pkr_we), .wr_addr(pkr_waddr), .wr_data(pkr_wdata),
        .rd_clk(g_clk), .rd_addr(rd_ptr[18:0]), .rd_data(fb_rd_data)
    );
`endif

    // ---- 读回校验：这一步不是装饰，是"BRAM 必须留在设计里"的唯一理由 ----
    // 第一版这里累加 rd_sum，而 rd_sum 又只喂给下面的 _unused_ok ⇒ 没有任何可观测终点，
    // 综合于是把整块帧缓存连同写路径一起裁掉，报出 "Block RAM 0.5 tile" 的**绿色但无意义**结果。
    // 现在用 XOR 折叠（空白缓存 XOR 出来恒为 0，只要真写进过非零像素就会变），
    // 并让 led[1] 必须是"帧完成 且 缓存内容确实变过"才亮 ⇒ 缓存被裁掉时 LED 表现不同，
    // 这条判据既保住了资源，也让"数据真的走通了一遍"在上板时可见。
    always @(posedge g_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 19'd0; rd_sum <= 32'd0; rd_xor <= 16'd0;
        end else begin
            rd_ptr <= rd_ptr + 19'd1;
            rd_sum <= rd_sum + {16'd0, fb_rd_data};
            rd_xor <= rd_xor ^ fb_rd_data;
        end
    end

    always @(posedge g_clk or negedge rst_n) begin
        if (!rst_n) begin
            xor_at_frame <= 16'd0; data_alive <= 1'b0;
        end else if (frame_done) begin
            data_alive    <= (rd_xor != xor_at_frame);
            xor_at_frame  <= rd_xor;
        end
    end

    // ---- 链路活性：RGMII RXC 有沿 ⇒ 网线插着。用它自己门控自己是最省事的判据 ----
    reg [23:0] hb_div;
    always @(posedge g_clk or negedge rst_n) begin
        if (!rst_n) hb_div <= 24'd0; else hb_div <= hb_div + 24'd1;
    end

    reg link_up;
    always @(posedge g_clk or negedge rst_n) begin
        if (!rst_n) link_up <= 1'b0;
        else if (g_rx_dv) link_up <= 1'b1;
    end

    reg frames_seen, err_seen;
    always @(posedge g_clk or negedge rst_n) begin
        if (!rst_n) begin
            frames_seen <= 1'b0; err_seen <= 1'b0;
        end else begin
            if (frame_done)   frames_seen <= 1'b1;
            if (reasm_fabort) err_seen    <= 1'b1;
        end
    end

    // ---- 遥测：每秒把上面的计数打包成一包 UDP 发给 PC（自研 ku5p_telem）----
    ku5p_telem #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_tlm (
        .clk(g_clk), .rst_n(rst_n),
        .stat_frames(s_frames), .stat_pkts(s_pkts), .stat_bytes(s_bytes),
        .stat_bad(s_badc), .stat_oob(s_oob), .rows_missed(reasm_rows_miss),
        .link_up(link_up), .frames_seen(frames_seen), .abort_seen(err_seen),
        .data_alive(data_alive), .peer_known(peer_known),
        .udp_rqs(tlm_rqs),
        .tx_start_en(udp_grant), .tx_req(udp_tx_req),
        .tx_data(tlm_data), .tx_byte_num(tlm_len)
    );

    // ---- GMII 发送仲裁（自研，替掉厂商 eth_ctrl 的那半段 mux）----
    ku5p_tx_arb u_arb (
        .clk(g_clk), .rst_n(rst_n),
        .arp_rqs(arp_rqs), .icmp_rqs(icmp_rqs), .udp_rqs(tlm_rqs),
        .arp_grant(arp_grant), .icmp_grant(icmp_grant), .udp_grant(udp_grant),
        .arp_done(arp_tx_done), .icmp_done(icmp_tx_done), .udp_done(udp_tx_done),
        .arp_tx_en(arp_gmii_tx_en),  .arp_txd(arp_gmii_txd),
        .icmp_tx_en(icmp_gmii_tx_en), .icmp_txd(icmp_gmii_txd),
        .udp_tx_en(udp_gmii_tx_en),  .udp_txd(udp_gmii_txd),
        .gmii_tx_en(g_tx_en), .gmii_txd(g_txd)
    );

    // LED：本板只有 4 个（原理图 p5/p16：LED1..4 = H9 J9 G11 H11，bank86 VCCO 3.3 V，
    // 高电平点亮）。低有效写法是为了"没接好时全亮"，一眼能看出配置没跑起来。
    //   led[0] 链路有流量     led[1] 收到过完整帧     led[2] 出现过拼帧失败     led[3] 心跳 ≈3.7 Hz
    // 遥测不在 LED 上表达：它能不能发出去，PC 侧 `ku5p_stats.mjs` 收到包就是判据，
    // 比"灯闪了一下"强得多。
    assign led[0] = ~link_up;
    assign led[1] = ~(frames_seen & data_alive);   // 帧完成 **且** 缓存内容变过
    assign led[2] = ~err_seen;
    assign led[3] = ~hb_div[23];
    wire _unused_ok = &{1'b0, s_pkts, s_bytes, s_oob, rd_sum, data_alive,
                        udp_tx_req, arp_tx_done, icmp_tx_done, g_tx_en, 1'b0};
endmodule
