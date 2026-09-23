`timescale 1ns/1ps
// 片源仲裁：DDR→帧缓存 这一台搬运机，到底归 ETH 引擎还是归 PS(SD/FILL) 引擎。
//
// 为什么要单独成模块：这件事的正确答案**不是**"哪边有数据"，而是"哪边活着 + 现在能不能安全换手"。
// 老写法是 `eth_mode = 3FF(|s_pkts)`，两个问题叠在一起：
//   ① |s_pkts 是"自配置以来收到过任何一个包"——PC 的 ARP 就够触发，且**拔网线也不会回 0**，
//      于是 PS 片源被永久锁死（ISSUES #47 修的是它在显示端的表现，这里修的是它的根）；
//   ② 就算换成"最近有包"，两个引擎共用同一个 AXI 读口 + 同一个 BRAM 写口，选择位在
//      一次拷贝**中途**翻转会留下半开的读突发：老代码里唯一的"互锁"就是那一个选择位本身。
// 所以这里把两件事分开：
//   · "活着"由 link_monitor 用 stall_ms 判（eth_rxc 域，本来就是它的活）；
//   · "换手"只在两个引擎都空闲时发生，且往 PS 方向带一段静默等待（滞回），
//     免得帧间隔刚好卡在阈值上时来回抢总线。
module src_arb #(
    // eth 静默多少拍才把总线让给 PS。AXI 域 100 MHz ⇒ 2_000_000 = 20 ms。
    // 注意这是**第二级**滞回：第一级是 stall_ms > LIVE_MS（默认 200 ms）。
    parameter integer T_OFF_CYC = 2_000_000
)(
    input  wire clk,          // axi_clk：两个引擎都在这个域
    input  wire rst_n,
    input  wire eth_live,     // 已在本域同步好的电平（慢变量，ms 级）
    input  wire row_busy,     // ETH 引擎（axi_frame_writer_gated）正在拷贝
    input  wire fill_busy,    // PS 引擎（axi_frame_writer64）正在拷贝
    output reg  owner_eth     // 1 = AXI 读口与帧缓存写口归 ETH 引擎
);
    reg [31:0] quiet;
    wire       both_idle = ~row_busy & ~fill_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            owner_eth <= 1'b0;      // 配置完成时两边都没东西，先给 PS
            quiet     <= 32'd0;
        end else begin
            // 计数器只服务"往 PS 让位"这一个方向；ETH 一活就清零（回抢不等）
            if (!eth_live) begin
                if (quiet != 32'hFFFF_FFFF) quiet <= quiet + 32'd1;
            end else quiet <= 32'd0;

            // 唯一的赋值点：只有两边都空闲才换主人 ⇒ 不会切断任何一次拷贝
            if (both_idle) begin
                if (eth_live)               owner_eth <= 1'b1;
                else if (quiet >= T_OFF_CYC) owner_eth <= 1'b0;
            end
        end
    end
endmodule
