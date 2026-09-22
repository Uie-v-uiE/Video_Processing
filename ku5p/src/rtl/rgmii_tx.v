// [KU5P 移植说明] 本文件逐字取自板卡厂商 RIGUKE 的 KU5P 例程
//   D:\Xilinx\Resource\KU5P\KU5P_DEMO\KU5P_DEMO_UDP_STACK\Source\gmii_to_rgmii\rgmii_tx.v
// 它给出 UltraScale+ 上 RGMII IO 的正确原语组合（BUFG+BUFIO+IDDRE1 / ODDRE1，无 IDELAY）。
// 本工程自研的 Zynq 版同一层用 IDELAYE2+IDDR，二者差别见 ku5p/README.md。
// 除本段注释外未做任何修改；再分发请保留厂商原始文件头。
//----------------------------------------------------------------------------------------
// File name:           rgmii_tx
// Last modified Date:  2024/11/22
// Last Version:        V1.0
// Descriptions:        RGMII发送模块
//----------------------------------------------------------------------------------------
// Created by:          riguke
// Created date:        2024/11/22
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
module rgmii_tx(
    //GMII发送端口
    input              gmii_tx_clk , //GMII发送时钟    
    input              gmii_tx_en  , //GMII输出数据有效信号
    input       [7:0]  gmii_txd    , //GMII输出数据        
    
    //RGMII发送端口
    output             rgmii_txc   , //RGMII发送数据时钟    
    output             rgmii_tx_ctl, //RGMII输出数据有效信号
    output      [3:0]  rgmii_txd     //RGMII输出数据     
    );

//*****************************************************
//**                    main code
//*****************************************************

assign rgmii_txc = gmii_tx_clk;

//输出双沿采样寄存器 (rgmii_tx_ctl)
ODDRE1 #(
      .IS_C_INVERTED     (1'b0),            // Optional inversion for C
      .IS_D1_INVERTED    (1'b0),            // Unsupported, do not use
      .IS_D2_INVERTED    (1'b0),            // Unsupported, do not use
      .SIM_DEVICE        ("ULTRASCALE"),    // Set the device version (ULTRASCALE, ULTRASCALE_PLUS, ULTRASCALE_PLUS_ES1,ULTRASCALE_PLUS_ES2)
      .SRVAL(1'b0)                          // Initializes the ODDRE1 Flip-Flops to the specified value (1'b0, 1'b1)
   )
   ODDRE1_tx_ctl (
      .Q     (rgmii_tx_ctl),    // 1-bit output: Data output to IOB
      .C     (gmii_tx_clk),     // 1-bit input: High-speed clock input
      .D1    (gmii_tx_en),      // 1-bit input: Parallel data input 1
      .D2    (gmii_tx_en),      // 1-bit input: Parallel data input 2
      .SR    (1'b0)             // 1-bit input: Active High Async Reset
   );

genvar i;
generate for (i=0; i<4; i=i+1)
    begin : txdata_bus
      ODDRE1 #(
      .IS_C_INVERTED(1'b0),      // Optional inversion for C
      .IS_D1_INVERTED(1'b0),     // Unsupported, do not use
      .IS_D2_INVERTED(1'b0),     // Unsupported, do not use
      .SIM_DEVICE("ULTRASCALE"), // Set the device version (ULTRASCALE, ULTRASCALE_PLUS, ULTRASCALE_PLUS_ES1,ULTRASCALE_PLUS_ES2)
      .SRVAL(1'b0)               // Initializes the ODDRE1 Flip-Flops to the specified value (1'b0, 1'b1)
   )
   ODDRE1_inst (
      .Q     (rgmii_txd[i]),      // 1-bit output: Data output to IOB
      .C     (gmii_tx_clk),       // 1-bit input: High-speed clock input
      .D1    (gmii_txd[i]),       // 1-bit input: Parallel data input 1
      .D2    (gmii_txd[4+i]),     // 1-bit input: Parallel data input 2
      .SR    (1'b0)               // 1-bit input: Active High Async Reset
   );             
    end
endgenerate
endmodule