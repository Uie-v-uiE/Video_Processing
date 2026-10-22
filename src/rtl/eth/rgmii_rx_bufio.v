`timescale 1ns/1ps
// rgmii_rx_bufio — RGMII 4-bit DDR -> GMII 8-bit SDR，采 Alex Forencich 的
// `ssio_ddr_in` 拓扑：IDDR 吃 BUFIO（短、区域时钟），fabric 吃 BUFG（全局），
// 两者同源但**不是同一棵树**。这是为了避开现路径（IDDR 与 fabric 同吃 BUFG）在
// 真实 RGMII 输入窗下 5 ns 级 DCD 的做法；IDELAY 不再使用，PHY 的 RXDLY strap
// 负责数据相对 RXC 的 2 ns 延迟。
//
// 代码来源：alexforencich/verilog-ethernet 的 `ssio_ddr_in.v` / `iddr.v`（MIT，
// 许可头保留在这两个文件里）。本文件只做端口拼装与位序映射。
module rgmii_rx_bufio #(
    parameter TARGET = "XILINX"   // synthesis: "XILINX"; simulation: "SIM"
)(
    input  wire       idelay_clk,  // 保留端口以兼容旧例化；本路径不用 IDELAY
    input  wire       rgmii_rxc,
    input  wire       rgmii_rx_ctl,
    input  wire [3:0] rgmii_rxd,
    output wire       gmii_rx_clk,
    output wire       gmii_rx_dv,
    output wire [7:0] gmii_rxd
);
    wire [4:0] q1, q2;

    ssio_ddr_in #(
        .TARGET            (TARGET),
        .IODDR_STYLE       ("IODDR"),
        .CLOCK_INPUT_STYLE ("BUFIO"),
        .WIDTH             (5)
    ) u_rx_ddr (
        .input_clk (rgmii_rxc),
        .input_d   ({rgmii_rx_ctl, rgmii_rxd}),
        .output_clk(gmii_rx_clk),
        .output_q1 (q1),
        .output_q2 (q2)
    );

    // 与现 rgmii_rx 同一口径：Q1 是正沿（字节低半），Q2 是负沿（高半）。
    assign gmii_rxd   = {q2[3:0], q1[3:0]};
    assign gmii_rx_dv = q1[4] & q2[4];
endmodule
