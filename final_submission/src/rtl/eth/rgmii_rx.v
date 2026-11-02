// rgmii_rx — RGMII(4bit DDR) → GMII(8bit SDR)。**采样沿这一处被改过**（#57/#80）。
// 位段：RXC 上升沿那半字节是字节低位、下降沿是高位（IDDR SAME_EDGE_PIPELINED：Q1=正沿、Q2=负沿）。
// 时钟域：rgmii_rxc 本身就是 GMII 侧的 125 MHz —— 现在 5 个 IDDR 与下游 fabric **吃同一只 BUFG**。
// 原来 IDDR 吃 BUFIO（SCD 3.171 ns）、fabric 吃 BUFG（DCD 4.854 ns），同频同相却分走两条树，
// 偏斜 +1.616 ns 由综合器插 hold buffer 硬补 ⇒ WHS 每次重建在 ±1 ps 上掷硬币（r62 量到 +0.001）。
// RX_CTL 仅当 gmii_rx_dv 用：RGMII 没有 GMII 的 RX_ER 通道，本模块交不出错误标志。
// ⚠ 改时钟源会**把采样沿往后推 1.683 ns**（BUFIO→BUFG 之差），所以数据侧必须补同样的量：
//   `idelay_clk` 是 200 MHz ⇒ 每拍 1/(32×200 MHz) = 156 ps ⇒ 1.683 ns ≈ 10.8 拍 ⇒ 取 +11 拍。
//   拍数只有一个出处：顶层 `system_top.v` 传下来的 `IDELAY_VALUE`（原来 15，现在是 15+11 = 26）。
//   这一处不在时序报告的管辖内（`src/constraints/` 里没有任何 `set_input_delay`）⇒ 报告只能证明
//   内部路径变好，采样点落没落在眼里必须由 1000M 实流量的 `bad`/`drop_words` 判。
// ⚠⚠ 上面那句前提（"没有 set_input_delay"）在 2026-10-03 被今天的工作改掉了，别再照它推理：
//   候选窗 `src/constraints/r114_io_async.xdc`（±0.500 ns，RGMII 规范给的沿对齐公差）+ 变体 B
//   （沿后 1.5–2.5 ns）都在快车道上量过了（件 board/output/io_roll_console5.txt、
//   r114_idelay_sweep_console.txt、r114_sweepB_console.txt；结论 ISSUES #282/#285）：
//     · 窗一建起来，`eth_rxc` 的 hold 立刻 -2.885 / 5 个失败端点，落点就是本模块的 u_iddr_rx_ctl/D；
//     · 报告里 DCD = 5.008 ns（正是第 4 行那只 BUFG），SCD = 0 ⇒ 当年"搬进 BUFG 消偏斜"这一步
//       在**没有片外窗**的口径下看着像修好了，窗建好后它变成"捕获沿比数据晚到 ~5 ns"的净损失；
//     · 数据侧没有出口：IDELAY 从 26 加到最大 31 档只买到 0.43 ns（实测斜率 ≈63 ps/tap），
//       而要把 hold 抬到 0 需要 ≈2.7 ns ⇒ 能动的只有捕获钟（ISSUES #285 的两条候选、任务 #194）。
//   还有一处对不上、我没有解释、只登记不圆场：第 8 行按 200 MHz 参考钟算的 156 ps/tap，
//   与实测斜率 ≈63 ps/tap（报告里 IDELAYE2 的 2.292 ns / 26 档 ≈ 88 ps/tap）三种数互不一致。
//   ⇒ 谁要再按"拍数 = 1.683 ns / 156 ps"推采样点，先把这条量清楚（未定，不当结论用）。
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

    //wire define
    wire       rgmii_rxc_bufg;  //全局时钟缓存
    wire [3:0] rgmii_rxd_delay;  //rgmii_rxd输入延时
    wire       rgmii_rx_ctl_delay;  //rgmii_rx_ctl输入延时
    wire [1:0] gmii_rxdv_t;  //两位GMII接收有效信号 

    assign gmii_rx_clk = rgmii_rxc_bufg;
    assign gmii_rx_dv  = gmii_rxdv_t[0] & gmii_rxdv_t[1];

    //全局时钟缓存：IDDR 与下游 fabric 都吃这一只，偏斜才是"同一棵树内的零点几 ns"
    BUFG BUFG_inst (
        .I(rgmii_rxc),      // 1-bit input: Clock input
        .O(rgmii_rxc_bufg)  // 1-bit output: Clock output
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
                .REGRST     (1'b0)                 // 1-bit input: Active-high reset tap-delay
            );

            IDDR #(
                .DDR_CLK_EDGE("SAME_EDGE_PIPELINED"),  // 同 u_iddr_rx_ctl
                .INIT_Q1     (1'b0),                   // Initial value of Q1: 1'b0 or 1'b1
                .INIT_Q2     (1'b0),                   // Initial value of Q2: 1'b0 or 1'b1
                .SRTYPE      ("SYNC")                  // Set/Reset type: "SYNC" or "ASYNC"
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
