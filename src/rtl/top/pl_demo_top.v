`timescale 1ns/1ps
// Pure-PL demo top: colorbar + full 0-359 rotate + effects + HDMI dual pane.
// No PS required. Default enable all effects for visible right-pane difference.
module pl_demo_top (
    input  wire       sys_clk,
    input  wire       key1_n,
    input  wire       key2_n,
    output wire [1:0] led,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n,
    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n
);
    // gray only by default — clearer left/right difference than invert+binary
    // （九级控制字是唯一的一套效果口径：老五位 `effect_en` 已经删掉，见 effect_ctrl.v 文件头）
    wire [8:0] stage_sel = 9'd1;
    wire [7:0] threshold = 8'd80;
    wire       src_sel   = 1'b0;

    pl_video_top #(
        .IMG_W(512), .IMG_H(300), .PANE_W(512), .BASE_ADDR(32'h1000_0000)
    ) u_pl (
        .sys_clk(sys_clk),
        .sys_rst_n(1'b1),
        .axi_clk(sys_clk),
        .axi_rst_n(1'b1),
        .stage_sel(stage_sel),
        .threshold(threshold),
        .src_sel(src_sel),
        .zoom_en(1'b1),
        // #83：pl_video_top 新增的 axi 域准静态输入，在这个"纯 PL 演示"顶层里没有 PS/GPIO ⇒
        //   钉 1'b1 = 与 r63b/r63c 的 localparam 默认**同一个行为**（双线性开）。
        //   不连就是悬空输入（综合成 0、仿真成 Z），门禁的 ports_check 会为它判红 ——
        //   这条红是它该红的样子：新加一口时必须两棵树一起接，否则"另一个顶层"就悄悄变了行为。
        .bilin_en_axi(1'b1),
        .zoom_sel_async(3'd0),       // 纯 PL 演示没有 PS：缩放留在自动呼吸
        .zoom_manual_async(1'b0),
        // #51：演示顶层不驱动分割线；V9 起这一束是 19 位（多出来的 5 位是 rot_auto/rot_speed/zoom_fit）。
        // ⚠ 位宽必须跟着端口走：`14'd0` 接 19 位端口，Verilog 静默零扩展 ⇒ 屏上看不出问题，
        //   而门禁第 12 项（顶层接线）会红 —— #57 那一族的病就是"字面量里写死的位宽"。
        .split_ctl(19'd0),
        .ps_publish(1'b0),          // 纯 PL 演示没有 PS：不发布，DDR 回放路径保持静默
        .mode_ovr(2'b00), .mode_ovr_tog(1'b0),   // 没有 PS ⇒ 片源模式只听按键环
        .key1_n(key1_n),
        .key2_n(key2_n),
        .led(led),
        .tmds_clk_p(tmds_clk_p),
        .tmds_clk_n(tmds_clk_n),
        .tmds_data_p(tmds_data_p),
        .tmds_data_n(tmds_data_n),
        .m_axi_araddr(),
        .m_axi_arid(),
        .m_axi_arlen(),
        .m_axi_arsize(),
        .m_axi_arburst(),
        .m_axi_arvalid(),
        .m_axi_arready(1'b0),
        .m_axi_rdata(64'd0),
        .m_axi_rid(6'd0),
        .m_axi_rresp(2'b00),
        .m_axi_rlast(1'b0),
        .m_axi_rvalid(1'b0),
        .m_axi_rready(),
        .eth_wr_clk(sys_clk),
        .eth_wr_en(1'b0),
        .eth_wr_addr(19'd0),
        .eth_wr_data(16'd0),
        .eth_link(1'b0),
        .eth_live(1'b0),          // 这个 top 没有 ETH 通路：仲裁从复位起就归 PS 侧
        .eth_tb_ok(1'b0),         // 同上：没有 eth_rxc，时基当然也不健康（#49/#52 那两个条件之一）
        .eth_frame(1'b0),
        .eth_commit(1'b0),        // 纯 PL 演示没有"收完一帧并提交"这回事 ⇒ 时延打点也不会开始
        .eth_ddr_base(32'd0),     // 同上：没有 DDR 片源可读（m_axi 那一组已经全部接地）
        // （r55）原来这里把 .eth_pkts/.eth_bad 钉成 16'd0 —— pl_video_top 上那两个口已删，
        // 因为它们在像素域只喂一段没有读者的"两级当总线"同步器（ISSUES #64）。
        // ---- V8 新增的四个口，纯 PL 演示一律取"最保守的静默值" ----
        // 这四个必须写出来：`build/check_ports.py`（门禁第 14 项）会把"输入悬空"判红，
        // 而悬空在这个仓库里的历史表现就是"设了没反应"那一类（#47/#55/#61）。
        //   stage_sel = 0  ⇒ effect_ctrl 的合流规则"PS 没意见" ⇒ 仍然用上面那五位老使能（gray）
        //   gamma_ctl = 0  ⇒ 级 0 的 en=0 ⇒ 逐位旁路；OSD 的 Gamma 那一格因此画 0.0（=没开）
        //   lat_arm   = 0  ⇒ 快照不武装；OSD 的 Latency 用的是另一条（每轮自动换算 + 翻转位），
        //                    所以这一格在纯 PL 演示里照样有数，只是上位机 lane25~29 读不到
        //   lm_bus/...     ⇒ V8-5 已经把这三个输入从 pl_video_top 上删了（像素域没人读它们），
        //                    这里跟着删 —— 留着就是"连了不存在的端口"，综合会直接报错
        .stage_sel(9'd0),
        .gamma_ctl(32'd0),
        .lat_arm(1'b0),
        .status()
    );
endmodule
