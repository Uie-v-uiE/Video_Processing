// gmii_to_rgmii — RGMII 物理层壳：收侧 IDDR(+IDELAY) 在恢复时钟域，发侧可选
//   ① 旧的"TXC = 恢复时钟、TXD 用 ODDR 同沿"（USE_MMCM_TX=0，仅为 A/B 留档）
//   ② MMCM 的 125 MHz / 90° 经 ODDR 发 TXC 与 TXD（USE_MMCM_TX=1，默认）
// 逻辑侧不再直接用 gmii_rx_clk；eth_udp_video_top 里的 gmii_rx_cdc 把字节搬到 clk_eth。
module gmii_to_rgmii (
    input        idelay_clk,    //IDELAY时钟
    //以太网GMII接口
    output       gmii_rx_clk,   //GMII接收时钟（PHY 恢复）
    output       gmii_rx_dv,    //GMII接收数据有效信号
    output [7:0] gmii_rxd,      //GMII接收数据
    output       gmii_tx_clk,   //GMII发送时钟（= tx_clk）
    input        gmii_tx_en,    //GMII发送数据使能信号
    input  [7:0] gmii_txd,      //GMII发送数据
    input        tx_clk,        //125 MHz 0°（MMCM）
    input        tx_clk90,      //125 MHz 90°
    //以太网RGMII接口
    input        rgmii_rxc,     //RGMII接收时钟
    input        rgmii_rx_ctl,  //RGMII接收数据控制信号
    input  [3:0] rgmii_rxd,     //RGMII接收数据
    output       rgmii_txc,     //RGMII发送时钟
    output       rgmii_tx_ctl,  //RGMII发送数据控制信号
    output [3:0] rgmii_txd      //RGMII发送数据
);
    parameter IDELAY_VALUE = 0;  //输入数据IO延时(如果为n,表示延时n*78ps)
    parameter CAPTURE_STYLE = "BUFG";
    parameter CAPTURE_TARGET = "XILINX";
    parameter USE_MMCM_TX = 1;   // 1 = clk/clk90 经 ODDR 发 TXC；0 = 旧路径（TXC=恢复钟）
    // "ODDR90" = TXC 由 clk90 过 ODDR（数据眼中心，表 60 的 TskewT 不允许）；
    // "ODDR0"  = TXC 由 clk 过 ODDR（0°，时钟/数据路径匹配，目标 TskewT ±0.5）；
    // "FWD0"   = TXC 直接转发 tx_clk（0°，板上已验证但时钟路径与数据不匹配）。
    parameter TX_STYLE = "ODDR0";

    //RGMII接收
    generate
    if (CAPTURE_STYLE == "BUFIO") begin : g_rx_bufio
        rgmii_rx_bufio #(
            .TARGET(CAPTURE_TARGET)
        ) u_rgmii_rx (
            .idelay_clk  (idelay_clk),
            .gmii_rx_clk (gmii_rx_clk),
            .rgmii_rxc   (rgmii_rxc),
            .rgmii_rx_ctl(rgmii_rx_ctl),
            .rgmii_rxd   (rgmii_rxd),
            .gmii_rx_dv  (gmii_rx_dv),
            .gmii_rxd    (gmii_rxd)
        );
    end else begin : g_rx_bufg
        rgmii_rx #(
            .IDELAY_VALUE(IDELAY_VALUE)
        ) u_rgmii_rx (
            .idelay_clk  (idelay_clk),
            .gmii_rx_clk (gmii_rx_clk),
            .rgmii_rxc   (rgmii_rxc),
            .rgmii_rx_ctl(rgmii_rx_ctl),
            .rgmii_rxd   (rgmii_rxd),
            .gmii_rx_dv(gmii_rx_dv),
            .gmii_rxd  (gmii_rxd)
        );
    end
    endgenerate

    //RGMII发送
    generate
    if (USE_MMCM_TX != 0 && TX_STYLE == "ODDR90") begin : g_tx_oddr
        rgmii_tx_oddr #(.TARGET(CAPTURE_TARGET)) u_rgmii_tx (
            .clk(tx_clk), .clk90(tx_clk90), .rst(1'b0),
            .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
            .rgmii_txc(rgmii_txc), .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txd(rgmii_txd)
        );
        assign gmii_tx_clk = tx_clk;
    end else if (USE_MMCM_TX != 0 && TX_STYLE == "ODDR0") begin : g_tx_oddr0
        // 0° 但时钟也过 ODDR：时钟/数据路径匹配，满足表 60 的 TskewT ±0.5 ns，同时保持板上
        // 验证过的 0° 相位（FWD0 的时钟是 BUFG 直接送 OBUF，与数据 ODDR 路径不匹配）。
        rgmii_tx_oddr #(.TARGET(CAPTURE_TARGET), .USE_CLK90(0)) u_rgmii_tx (
            .clk(tx_clk), .clk90(tx_clk90), .rst(1'b0),
            .gmii_tx_en(gmii_tx_en), .gmii_txd(gmii_txd),
            .rgmii_txc(rgmii_txc), .rgmii_tx_ctl(rgmii_tx_ctl), .rgmii_txd(rgmii_txd)
        );
        assign gmii_tx_clk = tx_clk;
    end else if (USE_MMCM_TX != 0) begin : g_tx_fwd0
        // 0° 转发：TXC 直接是 tx_clk，数据用同沿 ODDR（r135 以前上板验证过的相位）。
        rgmii_tx u_rgmii_tx (
            .gmii_tx_clk(tx_clk),
            .gmii_tx_en (gmii_tx_en),
            .gmii_txd   (gmii_txd),
            .rgmii_txc   (rgmii_txc),
            .rgmii_tx_ctl(rgmii_tx_ctl),
            .rgmii_txd   (rgmii_txd)
        );
        assign gmii_tx_clk = tx_clk;
    end else begin : g_tx_rxclk
        // 旧路径：TXC = 收侧恢复钟。只在 A/B 时用。
        rgmii_tx u_rgmii_tx (
            .gmii_tx_clk(gmii_rx_clk),
            .gmii_tx_en (gmii_tx_en),
            .gmii_txd   (gmii_txd),
            .rgmii_txc   (rgmii_txc),
            .rgmii_tx_ctl(rgmii_tx_ctl),
            .rgmii_txd   (rgmii_txd)
        );
        assign gmii_tx_clk = gmii_rx_clk;
    end
    endgenerate
endmodule
