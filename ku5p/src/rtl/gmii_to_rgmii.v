// [KU5P 移植说明] 本文件逐字取自板卡厂商 RIGUKE 的 KU5P 例程
//   D:\Xilinx\Resource\KU5P\KU5P_DEMO\KU5P_DEMO\07_UDP_STACK\Source\gmii_to_rgmii\gmii_to_rgmii.v
// 它给出 UltraScale+ 上 RGMII IO 的正确原语组合（BUFG+BUFIO+IDDRE1 / ODDRE1，无 IDELAY）。
// 本工程自研的 Zynq 版同一层用 IDELAYE2+IDDR，二者差别见 ku5p/README.md。
// 除本段注释外未做任何修改；再分发请保留厂商原始文件头。
//----------------------------------------------------------------------------------------
// File name:           gmii_to_rgmii
// Last modified Date:  2024/11/22
// Last Version:        V1.0
// Descriptions:        GMII接口转RGMII接口模块
//----------------------------------------------------------------------------------------
// Created by:          riguke
// Created date:        2024/11/22
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//
module gmii_to_rgmii(
    //以太网GMII接口
    output             gmii_rx_clk , //GMII接收时钟
    output             gmii_rx_dv  , //GMII接收数据有效信号
    output      [7:0]  gmii_rxd    , //GMII接收数据
    output             gmii_tx_clk , //GMII发送时钟
    input              gmii_tx_en  , //GMII发送数据使能信号
    input       [7:0]  gmii_txd    , //GMII发送数据            
    //以太网RGMII接口   
    input              rgmii_rxc   , //RGMII接收时钟
    input              rgmii_rx_ctl, //RGMII接收数据控制信号
    input       [3:0]  rgmii_rxd   , //RGMII接收数据
    output             rgmii_txc   , //RGMII发送时钟    
    output             rgmii_tx_ctl, //RGMII发送数据控制信号
    output      [3:0]  rgmii_txd     //RGMII发送数据          
    );

//*****************************************************
//**                    main code
//*****************************************************

assign gmii_tx_clk = gmii_rx_clk;

//RGMII接收
rgmii_rx u_rgmii_rx(
    .gmii_rx_clk   (gmii_rx_clk),
    .rgmii_rxc     (rgmii_rxc   ),
    .rgmii_rx_ctl  (rgmii_rx_ctl),
    .rgmii_rxd     (rgmii_rxd   ),
    
    .gmii_rx_dv    (gmii_rx_dv ),
    .gmii_rxd      (gmii_rxd   )
    );

//RGMII发送
rgmii_tx u_rgmii_tx(
    .gmii_tx_clk   (gmii_tx_clk ),
    .gmii_tx_en    (gmii_tx_en  ),
    .gmii_txd      (gmii_txd    ),
              
    .rgmii_txc     (rgmii_txc   ),
    .rgmii_tx_ctl  (rgmii_tx_ctl),
    .rgmii_txd     (rgmii_txd   )
    );

endmodule
