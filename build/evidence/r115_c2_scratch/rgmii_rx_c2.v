// rgmii_rx —— 【丢弃副本树上的 C2 证伪件，不在交付树里】
// r115 夜：把捕获沿**提前**约 5 ns（MMCM 负相移 −225° @ 125 MHz = 8 ns 周期的 5.000 ns），
// 让 IDDR 的 C 脚上的沿落回数据有效窗内部；IDDR 与下游 fabric 仍然吃**同一只 BUFG**（保住 r92/#57 的既得成果）。
//
// 为什么是这个数（全部来自实测，不来自猜）：
//   件 build/evidence/r114_sweepB/rt_tap0_eth_rxc_hold.rpt 把那条 −2.522 拆干净了：
//     arrival  3.476 = input_delay_min 1.500 + IBUF 1.321 + IDELAYE2 0.655
//     required 5.998 = DCD 5.008(IBUF 1.430 + 走线 1.873 + BUFG 0.085 + 走线 1.620) + 不确定度 0.835 + **IDDR 的 hold 0.155**
//   ⇒ 差额全在"捕获钟比 pad 沿晚到 5.008"这一项上；把沿提前 5.000 ⇒ 预测 hold 余量 +2.4、setup 余量 +4.2（**预测，待这一滚量**）。
//   数据侧确认没有出口：IDELAY 31 档上限只买到 2.7 ns 里的 0.43（件 r114_idelay_sweep_console.txt，斜率实测 ≈63 ps/tap）。
//
// 原注释保留在下面（交付树 src/rtl/eth/rgmii_rx.v 才是权威，这份只是证伪用的影子）。
//
// 原文件头（交付树里的那份）：
// rgmii_rx — RGMII(4bit DDR) → GMII(8bit SDR)。**采样沿这一处被改过**（#57/#80）。
// 位段：RXC 上升沿那半字节是字节低位、下降沿是高位（IDDR SAME_EDGE_PIPELINED：Q1=正沿、Q2=负沿）。
// 时钟域：rgmii_rxc 本身就是 GMII 侧的 125 MHz —— 现在 5 个 IDDR 与下游 fabric **吃同一只 BUFG**。
// RX_CTL 仅当 gmii_rx_dv 用：RGMII 没有 GMII 的 RX_ER 通道，本模块交不出错误标志。
module rgmii_rx (
    input idelay_clk,  //200Mhz时钟，IDELAY时钟

    //以太网RGMII接口
    input       rgmii_rxc,     //RGMII接收时钟
    input       rgmii_rx_ctl,  //RGMII接收数据控制信号
    input [3:0] rgmii_rxd,     //RGMII接收数据    

    //以太网GMII接口
    output       gmii_rx_clk,  //GMII接收时钟
    output       gmii_rx_dv,   //GMII接收数据有效信号
    output [7:0] gmii_rxd      //GMII接收数据   
);

    //parameter define
    parameter IDELAY_VALUE = 0;
    // C2 的相移角（度）。125 MHz ⇒ 360° = 8.000 ns ⇒ −225° = 提前 5.000 ns。
    // MMCM 的相位粒度 = 360/56 ≈ 6.4286° ⇒ 225° = 35 步，整除，没有取整误差。
    parameter RX_PHASE_DEG = -225.000;

    //wire define
    wire       rgmii_rxc_bufg;  //全局时钟缓存
    wire       mmcm_clk0;       //C2：被挪早 5 ns 的那一路
    wire       mmcm_fb;         //内部反馈
    wire [3:0] rgmii_rxd_delay;  //rgmii_rxd输入延时
    wire       rgmii_rx_ctl_delay;  //rgmii_rx_ctl输入延时
    wire [1:0] gmii_rxdv_t;  //两位GMII接收有效信号 

    assign gmii_rx_clk = rgmii_rxc_bufg;
    assign gmii_rx_dv  = gmii_rxdv_t[0] & gmii_rxdv_t[1];

    // ---- C2 的唯一结构改动：BUFG 前面插一只 MMCM，只做 1:1 变频 + 负相移 ----
    // VCO = 125 × 8 / 1 = 1000 MHz（-2 速度等级范围内），CLKOUT0 = 1000/8 = 125 MHz。
    MMCME2_BASE #(
        .BANDWIDTH        ("OPTIMIZED"),
        .CLKFBOUT_MULT_F  (8.000),
        .CLKFBOUT_PHASE   (0.000),
        .CLKIN1_PERIOD    (8.000),
        .CLKOUT0_DIVIDE_F (8.000),
        .CLKOUT0_DUTY_CYCLE(0.500),
        .CLKOUT0_PHASE    (RX_PHASE_DEG),
        .DIVCLK_DIVIDE    (1),
        .REF_JITTER1      (0.010),
        .STARTUP_WAIT     ("FALSE")
    ) u_mmcm_rx (
        .CLKOUT0  (mmcm_clk0),
        .CLKOUT1  (),
        .CLKOUT2  (),
        .CLKOUT3  (),
        .CLKOUT4  (),
        .CLKOUT5  (),
        .CLKOUT6  (),
        .CLKFBOUT (mmcm_fb),
        .CLKFBOUTB(),
        .CLKFBIN  (mmcm_fb),
        .CLKOUT0B (),
        .LOCKED   (),
        .PWRDWN   (1'b0),          // ⚠ MMCME2_BASE 的端口是 PWRDWN，不是 ADV 的 PWRONINT
                                   //   （23:35 实测：写成 PWRONINT 时综合报 [Synth 8-11365] named port
                                   //    connection 'PWRONINT' does not exist，然后整条模块链级联失败。
                                   //    正确写法在本仓 `src/rtl/clocks/clk_gen.v:48`，先抄再改。）
        .CLKIN1   (rgmii_rxc),
        .RST      (1'b0)
    );

    //全局时钟缓存：IDDR 与下游 fabric 都吃这一只，偏斜才是"同一棵树内的零点几 ns"
    BUFG BUFG_inst (
        .I(mmcm_clk0),        // C2：原来是 rgmii_rxc（IBUF 出来的那一路）
        .O(rgmii_rxc_bufg)
    );

    //输入延时控制
    // Specifies group name for associated IDELAYs/ODELAYs and IDELAYCTRL
    (* IODELAY_GROUP = "rgmii_rx_delay" *)
    IDELAYCTRL IDELAYCTRL_inst (
        .RDY   (),            // 1-bit output: Ready output
        .REFCLK(idelay_clk),  // 1-bit input: Reference clock input
        .RST   (1'b0)         // 1-bit input: Active high reset input
    );

    //rgmii_rx_ctl输入延时与双沿采样
    (* IODELAY_GROUP = "rgmii_rx_delay" *)
    IDELAYE2 #(
        .IDELAY_TYPE     ("FIXED"),       // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
        .IDELAY_VALUE    (IDELAY_VALUE),  // Input delay tap setting (0-31)
        .REFCLK_FREQUENCY(200.0)          // IDELAYCTRL clock input frequency in MHz 
    ) u_delay_rx_ctrl (
        .CNTVALUEOUT(),                    // 5-bit output: Counter value output
        .DATAOUT    (rgmii_rx_ctl_delay),  // 1-bit output: Delayed data output
        .C          (1'b0),                // 1-bit input: Clock input
        .CE         (1'b0),                // 1-bit input: enable increment/decrement
        .CINVCTRL   (1'b0),                // 1-bit input: Dynamic clock inversion input
        .CNTVALUEIN (5'b0),                // 5-bit input: Counter value input
        .DATAIN     (1'b0),                // 1-bit input: Internal delay data input
        .IDATAIN    (rgmii_rx_ctl),        // 1-bit input: Data input from the I/O
        .INC        (1'b0),                // 1-bit input: Increment / Decrement tap delay
        .LD         (1'b0),                // 1-bit input: Load IDELAY_VALUE input
        .LDPIPEEN   (1'b0),                // 1-bit input: Enable PIPELINE register
        .REGRST     (1'b0)                 // 1-bit input: Active-high reset tap-delay input
    );

    //rx_ctl 双沿采样：Q1=正沿、Q2=负沿，两沿都为 1 才算 dv（见上面的 assign）
    IDDR #(
        .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),  // "OPPOSITE_EDGE" / "SAME_EDGE" / "SAME_EDGE_PIPELINED"
        .INIT_Q1     (1'b0),                   // Initial value of Q1: 1'b0 or 1'b1
        .INIT_Q2     (1'b0),                   // Initial value of Q2: 1'b0 or 1'b1
        .SRTYPE      ("SYNC")                  // Set/Reset type: "SYNC" or "ASYNC"
    ) u_iddr_rx_ctl (
        .Q1(gmii_rxdv_t[0]),      // 1-bit output for positive edge of clock
        .Q2(gmii_rxdv_t[1]),      // 1-bit output for negative edge of clock
        .C (rgmii_rxc_bufg),     // 1-bit clock input
        .CE(1'b1),                // 1-bit clock enable input
        .D (rgmii_rx_ctl_delay),  // 1-bit DDR data input
        .R (1'b0),                // 1-bit reset
        .S (1'b0)                 // 1-bit set
    );

    //rgmii_rxd输入延时与双沿采样
    genvar i;
    generate
        for (i = 0; i < 4; i = i + 1) (* IODELAY_GROUP = "rgmii_rx_delay" *) begin : rxdata_bus
            //输入延时           
            (* IODELAY_GROUP = "rgmii_rx_delay" *)
            IDELAYE2 #(
                .IDELAY_TYPE     ("FIXED"),       // FIXED,VARIABLE,VAR_LOAD,VAR_LOAD_PIPE
                .IDELAY_VALUE    (IDELAY_VALUE),  // Input delay tap setting (0-31)    
                .REFCLK_FREQUENCY(200.0)          // IDELAYCTRL clock input frequency in MHz
            ) u_delay_rxd (
                .CNTVALUEOUT(),                    // 5-bit output: Counter value output
                .DATAOUT    (rgmii_rxd_delay[i]),  // 1-bit output: Delayed data output
                .C          (1'b0),                // 1-bit input: Clock input
                .CE         (1'b0),                // 1-bit input: enable increment/decrement
                .CINVCTRL   (1'b0),                // 1-bit input: Dynamic clock inversion
                .CNTVALUEIN (5'b0),                // 5-bit input: Counter value input
                .DATAIN     (1'b0),                // 1-bit input: Internal delay data input
                .IDATAIN    (rgmii_rxd[i]),        // 1-bit input: Data input from the I/O
                .INC        (1'b0),                // 1-bit input: Inc/Decrement tap delay
                .LD         (1'b0),                // 1-bit input: Load IDELAY_VALUE input
                .LDPIPEEN   (1'b0),                // 1-bit input: Enable PIPELINE register
                .REGRST     (1'b0)                 // 1-bit input: Active-high reset tap-delay input
            );

            IDDR #(
                .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),  // 同 u_iddr_rx_ctl
                .INIT_Q1     (1'b0),                   // Initial value of Q1: 1'b0 or 1'b1
                .INIT_Q2     (1'b0),                   // Initial value of Q2: 1'b0 or 1'b1
                .SRTYPE      ("SYNC")
            ) u_iddr_rxd (
                .Q1(gmii_rxd[i]),         // 1-bit output for positive edge of clock
                .Q2(gmii_rxd[4+i]),       // 1-bit output for negative edge of clock
                .C (rgmii_rxc_bufg),     // 1-bit clock input：与下游 fabric 同一棵树
                .CE(1'b1),                // 1-bit clock enable input
                .D (rgmii_rxd_delay[i]),  // 1-bit DDR data input
                .R (1'b0),                // 1-bit reset
                .S (1'b0)                 // 1-bit set
            );
        end
    endgenerate

endmodule
