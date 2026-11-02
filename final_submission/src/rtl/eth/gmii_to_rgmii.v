// gmii_to_rgmii — 纯连线壳：把厂商的 rgmii_rx / rgmii_tx 拼在一起，并让 gmii_tx_clk = gmii_rx_clk
//（RGMII 只有 RXC/TXC 两根时钟，这里 TX 侧沿用的是收侧恢复出来的那一路 125 MHz ⇒ 整个 ETH 逻辑
// 实际是**单时钟域**，各模块里的"tx 域"就是 rx 域）。。
module gmii_to_rgmii (
    input        idelay_clk,    //IDELAY时钟
    //以太网GMII接口
    output       gmii_rx_clk,   //GMII接收时钟
    output       gmii_rx_dv,    //GMII接收数据有效信号
    output [7:0] gmii_rxd,      //GMII接收数据
    output       gmii_tx_clk,   //GMII发送时钟
    input        gmii_tx_en,    //GMII发送数据使能信号
    input  [7:0] gmii_txd,      //GMII发送数据            
    //以太网RGMII接口   
    input        rgmii_rxc,     //RGMII接收时钟
    input        rgmii_rx_ctl,  //RGMII接收数据控制信号
    input  [3:0] rgmii_rxd,     //RGMII接收数据
    output       rgmii_txc,     //RGMII发送时钟    
    output       rgmii_tx_ctl,  //RGMII发送数据控制信号
    output [3:0] rgmii_txd      //RGMII发送数据          
);

    //parameter define
    parameter IDELAY_VALUE = 0;  //输入数据IO延时(如果为n,表示延时n*78ps) 

    assign gmii_tx_clk = gmii_rx_clk;   // TX 侧不发自己的时钟，见文件头

    //RGMII接收
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

    //RGMII发送
    rgmii_tx u_rgmii_tx (
        .gmii_tx_clk(gmii_tx_clk),
        .gmii_tx_en (gmii_tx_en),
        .gmii_txd   (gmii_txd),

        .rgmii_txc   (rgmii_txc),
        .rgmii_tx_ctl(rgmii_tx_ctl),
        .rgmii_txd   (rgmii_txd)
    );

endmodule
