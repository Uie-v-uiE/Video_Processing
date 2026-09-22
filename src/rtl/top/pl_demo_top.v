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
    wire [4:0] effect_en = 5'b00001;
    wire [7:0] threshold = 8'd80;
    wire       src_sel   = 1'b0;

    pl_video_top #(
        .IMG_W(512), .IMG_H(300), .PANE_W(512), .BASE_ADDR(32'h1000_0000)
    ) u_pl (
        .sys_clk(sys_clk),
        .sys_rst_n(1'b1),
        .axi_clk(sys_clk),
        .axi_rst_n(1'b1),
        .effect_en(effect_en),
        .threshold(threshold),
        .src_sel(src_sel),
        .zoom_en(1'b1),
        .ps_publish(1'b0),          // 纯 PL 演示没有 PS：不发布，DDR 回放路径保持静默
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
        .eth_frame(1'b0),
        .eth_pkts(16'd0),
        .eth_bad(16'd0),
        // 这个 top 没有 ETH 链路：心跳恒 0 ⇒ snap_cross 判定时钟消失 ⇒
        // OSD 的 STALL 显示 9999（"没有流"），这正是它该说的话。
        .lm_bus(320'd0), .lm_bus_tog(1'b0), .lm_hb(1'b0),
        .status()
    );
endmodule
