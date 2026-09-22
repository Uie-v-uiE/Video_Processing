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
    parameter IMG_W      = 512,
    parameter IMG_H      = 300,
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

    // ---- ARP / ICMP / UDP：这一段与 Zynq 版逐行同构（含 ICMP 回包的那个 20 拍延时） ----
    wire        arp_rx_done, arp_rx_type, arp_tx_en, arp_tx_done, arp_gmii_tx_en;
    wire [47:0] src_mac;
    wire [31:0] src_ip;
    wire [7:0]  arp_gmii_txd;

    wire        icmp_rec_pkt_done, icmp_rec_en, icmp_tx_done, icmp_tx_req, icmp_gmii_tx_en;
    wire [7:0]  icmp_rec_data, icmp_gmii_txd, icmp_fifo_q;
    wire [15:0] icmp_rec_byte_num;
    reg  [15:0] icmp_tx_byte_num;
    reg  [5:0]  icmp_dly;
    reg         icmp_tx_start_en;
    always @(posedge g_clk or negedge rst_n) begin
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

    wire        udp_rec_pkt_done, udp_rec_en, udp_gmii_tx_en, udp_tx_done, udp_tx_req;
    wire [7:0]  udp_rec_data, udp_gmii_txd;
    wire [15:0] udp_rec_byte_num;
    wire        fifo_rec_en;
    wire [7:0]  fifo_tx_data, fifo_rec_data;
    wire        fifo_tx_req;

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
        .arp_tx_en(arp_tx_en), .arp_tx_type(1'b1),
        .des_mac(src_mac), .des_ip(src_ip), .tx_done(arp_tx_done)
    );

    icmp #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)) u_icmp (
        .rst_n(rst_n),
        .gmii_rx_clk(g_clk), .gmii_rx_dv(g_rx_dv), .gmii_rxd(g_rxd),
        .gmii_tx_clk(g_tx_clk), .gmii_tx_en(icmp_gmii_tx_en), .gmii_txd(icmp_gmii_txd),
        .rec_pkt_done(icmp_rec_pkt_done), .rec_en(icmp_rec_en), .rec_data(icmp_rec_data),
        .rec_byte_num(icmp_rec_byte_num),
        .tx_start_en(icmp_tx_start_en), .tx_data(icmp_fifo_q),
        .tx_byte_num(icmp_tx_byte_num),
        .des_mac(src_mac), .des_ip(src_ip),
        .tx_done(icmp_tx_done), .tx_req(icmp_tx_req)
    );

    udp #(.BOARD_MAC(BOARD_MAC), .BOARD_IP(BOARD_IP)) u_udp (
        .rst_n(rst_n),
        .gmii_rx_clk(g_clk), .gmii_rx_dv(g_rx_dv), .gmii_rxd(g_rxd),
        .gmii_tx_clk(g_tx_clk), .gmii_tx_en(udp_gmii_tx_en), .gmii_txd(udp_gmii_txd),
        .rec_pkt_done(udp_rec_pkt_done), .rec_en(udp_rec_en), .rec_data(udp_rec_data),
        .rec_byte_num(udp_rec_byte_num),
        .tx_start_en(1'b0), .tx_data(8'd0), .tx_byte_num(16'd0),
        .des_mac(src_mac), .des_ip(src_ip),
        .tx_done(udp_tx_done), .tx_req(udp_tx_req)
    );

    eth_ctrl u_ctrl (
        .clk(g_clk), .rst_n(rst_n),
        .arp_rx_done(arp_rx_done), .arp_rx_type(arp_rx_type),
        .arp_tx_en(arp_tx_en), .arp_tx_type(), .arp_tx_done(arp_tx_done),
        .arp_gmii_tx_en(arp_gmii_tx_en), .arp_gmii_txd(arp_gmii_txd),
        .icmp_tx_start_en(icmp_tx_start_en), .icmp_tx_done(icmp_tx_done),
        .icmp_gmii_tx_en(icmp_gmii_tx_en), .icmp_gmii_txd(icmp_gmii_txd),
        .icmp_rec_en(icmp_rec_en), .icmp_rec_data(icmp_rec_data),
        .icmp_tx_req(icmp_tx_req), .icmp_tx_data(),
        .udp_tx_start_en(1'b0), .udp_tx_done(udp_tx_done),
        .udp_gmii_tx_en(udp_gmii_tx_en), .udp_gmii_txd(udp_gmii_txd),
        .udp_rec_data(udp_rec_data), .udp_rec_en(udp_rec_en),
        .udp_tx_req(udp_tx_req), .udp_tx_data(),
        .tx_data(fifo_tx_data), .tx_req(fifo_tx_req),
        .rec_en(fifo_rec_en), .rec_data(fifo_rec_data),
        .gmii_tx_en(g_tx_en), .gmii_txd(g_txd)
    );

    // ---- offset 拼帧（与 Zynq 版同一模块、同一判据） ----
    wire        fb_wr_en;
    wire [18:0] fb_wr_addr;   // 像素号
    wire [15:0] fb_wr_data;
    wire        reasm_flush, frame_done, reasm_ferr, reasm_fabort;
    wire [15:0] reasm_rows_miss;
    wire [31:0] s_frames, s_pkts, s_bytes, s_badc, s_oob;

    reg in_udp_pkt;
    always @(posedge g_clk or negedge rst_n) begin
        if (!rst_n) in_udp_pkt <= 1'b0;
        else if (udp_rec_pkt_done) in_udp_pkt <= 1'b0;
        else if (udp_rec_en) in_udp_pkt <= 1'b1;
    end
    wire udp_sof = udp_rec_en && !in_udp_pkt;

    frame_reasm #(.IMG_W(IMG_W), .IMG_H(IMG_H)) u_reasm (
        .clk(g_clk), .rst_n(rst_n),
        .p_data(udp_rec_data), .p_valid(udp_rec_en),
        .p_sof(udp_sof), .p_eof(udp_rec_pkt_done), .p_good(1'b1),
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
    frame_buffer_w64 #(.W(IMG_W), .H(IMG_H)) u_fb (
        .wr_clk(g_clk),
        .wr_en(pkr_we), .wr_addr(pkr_waddr), .wr_data(pkr_wdata),
        .rd_clk(g_clk), .rd_addr(rd_ptr[18:0]), .rd_data(fb_rd_data)
    );

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

    // LED：本板只有 4 个（原理图 p5/p16：LED1..4 = H9 J9 G11 H11，bank86 VCCO 3.3 V，
    // 高电平点亮）。低有效写法是为了"没接好时全亮"，一眼能看出配置没跑起来。
    //   led[0] 链路有流量     led[1] 收到过完整帧     led[2] 出现过拼帧失败     led[3] 心跳 ≈3.7 Hz
    assign led[0] = ~link_up;
    assign led[1] = ~(frames_seen & data_alive);   // 帧完成 **且** 缓存内容变过
    assign led[2] = ~err_seen;
    assign led[3] = ~hb_div[23];
    wire _unused_ok = &{1'b0, s_pkts, s_bytes, s_oob, rd_sum, data_alive, fifo_rec_en, fifo_rec_data,
                        fifo_tx_data, fifo_tx_req, udp_tx_req, udp_tx_done, arp_tx_done,
                        icmp_tx_done, g_tx_en, 1'b0};
endmodule
