`timescale 1ns/1ps
// tb_eth_top_rgmii — 上板同构的 RGMII 字节级闭环：
//   假 PHY 在 RGMII 双沿上发一个 ARP request（目标 192.168.1.10）
//   → IDDR/IDELAY（sim/prim 的行为模型）→ gmii_rx_cdc → 协议栈（clk_eth）
//   → ARP 应答 → rgmii_tx_oddr（clk/clk90）→ TB 在 rgmii_txc 双沿上收字节。
// 判据：收到完整 ARP reply，dest/src MAC、oper=2、sender IP=192.168.1.10、target IP=192.168.1.100。
// 这个台架是 r136 时钟域改版（恢复钟→clk_eth）的**板级形状**仿真：新路径只在硬件上红过，
// 必须在同一形状下重现，才能把"时钟/复位/桥"与"PHY 模拟"分开。
module tb_eth_top_rgmii;
    reg rxc = 0, eth_clk = 0, eth_clk90 = 0, axi_clk = 0, idelay_clk = 0;
    always #4.000 rxc = ~rxc;
    always #4.000 eth_clk = ~eth_clk;
    initial begin #2.0; forever #4.000 eth_clk90 = ~eth_clk90; end
    always #5.000 axi_clk = ~axi_clk;
    always #2.500 idelay_clk = ~idelay_clk;

    reg rst_n = 0, axi_rst_n = 0;
    initial begin
        repeat (40) @(posedge rxc);
        rst_n = 1; axi_rst_n = 1;
    end

    reg [3:0] rxd = 0;
    reg       rxc_ctl = 0;

    wire        tx_clk, tx_ctl;
    wire [3:0]  txd;
    wire [31:0] ddr_base;
    wire        commit, link;
    wire [319:0] lm_bus;
    wire        lm_tog, lm_hb;

    wire        m_awvalid, m_wvalid, m_bready;
    wire [31:0] m_awaddr;
    wire [7:0]  m_awlen, m_wstrb;
    wire [2:0]  m_awsize;
    wire [1:0]  m_awburst;
    wire [63:0] m_wdata;

    eth_udp_video_top #(
        .IMG_W(512), .IMG_H(300), .BASE_ADDR(32'h1000_0000),
        .IDELAY_VALUE(0), .CAPTURE_STYLE("BUFG"),
        .CAPTURE_TARGET("SIM"), .USE_MMCM_CLK(1),
        // 测生产目标 ODDR0：0° 同沿、时钟也过 ODDR；TB 在 TXC 沿后 0.2 ns 采，
        // 只验证字节序与协议，不代替 PHY 的 TskewT。
        .TX_STYLE("ODDR0")
    ) dut (
        .rgmii_rxc(rxc), .rst_n(rst_n),
        .axi_clk(axi_clk), .axi_rst_n(axi_rst_n),
        .idelay_clk(idelay_clk), .eth_clk(eth_clk), .eth_clk90(eth_clk90),
        .copy_hold(1'b0),
        .rgmii_rx_ctl(rxc_ctl), .rgmii_rxd(rxd),
        .rgmii_tx_clk(tx_clk), .rgmii_tx_ctl(tx_ctl), .rgmii_txd(txd),
        .frame_done(), .link_active(link),
        .ddr_commit_base(ddr_base), .ddr_commit_pulse(commit),
        .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen), .m_axi_awsize(m_awsize),
        .m_axi_awburst(m_awburst), .m_axi_awvalid(m_awvalid), .m_axi_awready(1'b1),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(), .m_axi_wvalid(m_wvalid),
        .m_axi_wready(1'b1), .m_axi_bvalid(1'b0), .m_axi_bready(m_bready),
        .stat_frames(), .stat_pkts(), .stat_bytes(), .stat_bad(),
        .lm_bus(lm_bus), .lm_bus_tog(lm_tog), .lm_hb(lm_hb),
        .lat_ms_axi(16'd0), .lat_ok_axi(1'b0),
        .lat_sticky_axi(1'b0), .lat_tog_axi(1'b0),
        .pane_bad_pix(16'd0), .pane_valid_pix(1'b0), .pane_tog_pix(1'b0),
        .gapclr_sel(1'b0)
    );

    // ---------------- 假 PHY：RGMII 收 ----------------
    task phy_byte;
        input [7:0] b;
        begin
            @(negedge rxc); #0.2; rxd = b[3:0]; rxc_ctl = 1'b1;
            @(posedge rxc); #0.2; rxd = b[7:4]; rxc_ctl = 1'b1;
        end
    endtask

    function [31:0] crc32b;
        input [31:0] c;
        input [7:0]  d;
        integer i;
        reg [31:0] x;
        begin
            x = c ^ d;
            for (i = 0; i < 8; i = i + 1)
                x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32b = x;
        end
    endfunction

    reg [7:0] frame [0:127];
    integer fi, nframe;
    reg [31:0] crc;

    task build_arp_req;
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1) frame[k] = (k == 7) ? 8'hD5 : 8'h55;
            // Ethernet
            frame[8]=8'hFF; frame[9]=8'hFF; frame[10]=8'hFF; frame[11]=8'hFF; frame[12]=8'hFF; frame[13]=8'hFF;
            frame[14]=8'h00; frame[15]=8'hAA; frame[16]=8'hBB; frame[17]=8'hCC; frame[18]=8'hDD; frame[19]=8'hEE;
            frame[20]=8'h08; frame[21]=8'h06;
            // ARP request
            frame[22]=8'h00; frame[23]=8'h01;   // htype
            frame[24]=8'h08; frame[25]=8'h00;   // ptype
            frame[26]=8'h06; frame[27]=8'h04;   // hlen/plen
            frame[28]=8'h00; frame[29]=8'h01;   // oper=request
            frame[30]=8'h00; frame[31]=8'hAA; frame[32]=8'hBB; frame[33]=8'hCC; frame[34]=8'hDD; frame[35]=8'hEE;
            frame[36]=8'd192; frame[37]=8'd168; frame[38]=8'd1; frame[39]=8'd100;
            frame[40]=0; frame[41]=0; frame[42]=0; frame[43]=0; frame[44]=0; frame[45]=0;
            frame[46]=8'd192; frame[47]=8'd168; frame[48]=8'd1; frame[49]=8'd10;
            // pad to 60 bytes payload (8..67), then FCS at 68..71
            for (k = 50; k < 68; k = k + 1) frame[k] = 8'h00;
            crc = 32'hFFFFFFFF;
            for (k = 8; k < 68; k = k + 1) crc = crc32b(crc, frame[k]);
            crc = ~crc;
            frame[68] = crc[7:0]; frame[69] = crc[15:8];
            frame[70] = crc[23:16]; frame[71] = crc[31:24];
            nframe = 72;
        end
    endtask

    task send_frame;
        integer k;
        begin
            for (k = 0; k < nframe; k = k + 1) phy_byte(frame[k]);
            @(posedge rxc); #0.2; rxc_ctl = 1'b0; rxd = 4'h0;
            repeat (30) @(posedge rxc);
        end
    endtask

    // ---------------- 假 PHY：RGMII 发 ----------------
    reg [3:0] lo_q = 0, hi_q = 0;
    reg       cp = 0, cn = 0;
    reg [7:0] txq [0:255];
    integer tw = 0;

    // RGMII 发侧：低半字节在 TXC 上升沿、高半字节在下降沿。一个字节必须在**下降沿**
    // 用"刚采到的高半字节 + 上一个上升沿采到的低半字节"拼，不能在上升沿拼（那会把
    // 上一个字节的高半字节配进来，整条流左移 4 bit）。
    always @(posedge tx_clk) begin
        #0.2;
        lo_q = txd; cp = tx_ctl;
    end
    always @(negedge tx_clk) begin
        #0.2;
        hi_q = txd; cn = tx_ctl;
        if (cp && cn && (tw < 256)) begin
            txq[tw] = {hi_q, lo_q};
            tw = tw + 1;
        end
    end

    integer errors = 0;
    integer i;
    initial begin
        build_arp_req;
        repeat (100) @(posedge rxc);
        send_frame;
        repeat (400) @(posedge rxc);
        if (tw < 60) begin
            $display("FAIL no ARP reply (tx bytes=%0d)", tw);
            errors = errors + 1;
        end else begin
            // txq[0..7]=preamble/SFD, [8..]=reply
            if (!(txq[8]==8'h00 && txq[9]==8'hAA && txq[10]==8'hBB &&
                  txq[11]==8'hCC && txq[12]==8'hDD && txq[13]==8'hEE)) begin
                $display("FAIL reply dest MAC %02x:%02x:%02x:%02x:%02x:%02x",
                         txq[8],txq[9],txq[10],txq[11],txq[12],txq[13]);
                errors = errors + 1;
            end
            if (!(txq[14]==8'h00 && txq[15]==8'h11 && txq[16]==8'h22 &&
                  txq[17]==8'h33 && txq[18]==8'h44 && txq[19]==8'h55)) begin
                $display("FAIL reply src MAC");
                errors = errors + 1;
            end
            if (!(txq[28]==8'h00 && txq[29]==8'h02)) begin
                $display("FAIL ARP oper=%02x%02x (expect 0002 reply)", txq[28], txq[29]);
                errors = errors + 1;
            end
            if (!(txq[36]==8'd192 && txq[37]==8'd168 && txq[38]==8'd1 && txq[39]==8'd10)) begin
                $display("FAIL sender IP %0d.%0d.%0d.%0d", txq[36],txq[37],txq[38],txq[39]);
                errors = errors + 1;
            end
            if (!(txq[46]==8'd192 && txq[47]==8'd168 && txq[48]==8'd1 && txq[49]==8'd100)) begin
                $display("FAIL target IP %0d.%0d.%0d.%0d", txq[46],txq[47],txq[48],txq[49]);
                errors = errors + 1;
            end
        end
        if (errors == 0) $display("PASS tb_eth_top_rgmii tx_bytes=%0d", tw);
        else             $display("FAIL tb_eth_top_rgmii errors=%0d", errors);
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL tb_eth_top_rgmii timeout tx_bytes=%0d", tw);
        $finish;
    end
endmodule
