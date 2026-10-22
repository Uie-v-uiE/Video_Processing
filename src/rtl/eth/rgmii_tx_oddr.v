`timescale 1ns/1ps
// rgmii_tx_oddr — RGMII TX 以 clk(0°) 发数据、clk90(90°) 发时钟，两者都过 ODDR。
//
// 旧实现是 `assign rgmii_txc = gmii_tx_clk` 且 TX 逻辑吃**收侧恢复出来的时钟**：
// TXC 是一根由 fabric 直接送出的 125 MHz，和数据之间没有可约束的相位关系（XDC 里
// eth_txd/tx_ctl/tx_clk 全是 set_false_path）；链路断了 RX 钟还会退化/停，TX 跟着没钟。
// 现在 TXC 与 TXD 都从 MMCM 的 clk/clk90 出发：时钟沿落在数据眼中心，可以用
// create_generated_clock + set_output_delay 真正约束。
module rgmii_tx_oddr #(
    parameter TARGET = "XILINX",
    // 1 = 时钟用 clk90（90° 居中）；0 = 时钟用 clk（0°，与数据同沿，RTL8211F 表 60 的 TskewT 模式）
    parameter USE_CLK90 = 1
)(
    input  wire       clk,
    input  wire       clk90,
    input  wire       rst,
    input  wire       gmii_tx_en,
    input  wire [7:0] gmii_txd,
    output wire       rgmii_txc,
    output wire       rgmii_tx_ctl,
    output wire [3:0] rgmii_txd
);
    // 时钟：d1=1/d2=0 的 ODDR 输出 125 MHz。两种相位：
    //   USE_CLK90=1：clk90 ⇒ 数据眼中心（RGMII 规范推荐，但本板 RTL8211F 不吃）；
    //   USE_CLK90=0：clk   ⇒ 与数据同沿（表 60 TskewT ±0.5 ns），时钟和数据都过 ODDR，路径匹配。
    oddr #(.TARGET(TARGET), .IODDR_STYLE("IODDR"), .WIDTH(1)) u_clk_oddr (
        .clk(USE_CLK90 != 0 ? clk90 : clk), .d1(1'b1), .d2(1'b0), .q(rgmii_txc)
    );

    oddr #(.TARGET(TARGET), .IODDR_STYLE("IODDR"), .WIDTH(5)) u_data_oddr (
        .clk(clk),
        .d1({gmii_txd[3:0], gmii_tx_en}),
        .d2({gmii_txd[7:4], gmii_tx_en}),
        .q({rgmii_txd, rgmii_tx_ctl})
    );
endmodule
