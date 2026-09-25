`timescale 1ns/1ps
// unisims_sim.v —— 仿真用的厂商原语**占位模型**（本机 xsim 没有 UNISIM 库）
//
// 与 sim/prim/MMCME2_BASE.v 同一件事的延续：`pl_video_top` 的树里除了 MMCM 还有
// BUFG / OBUFDS / OSERDESE2（`rgb2dvi` 的串行化那一级），而 `xelab` 报
// `Module <BUFG> not found` ⇒ 顶层根本起不来（2026-09-25 实测）。
//
// ⚠ 这三个模型是**故意不做实事**的，看下面每一条的"不建模"说明：
//   · 允许用它们的前提是"判据读的是并行像素，不读 DVI 引脚上的比特"；
//   · 谁哪天要判 DVI 串行输出的正确性，必须换真模型（或换有 UNISIM 的仿真器），
//     而不是把判据挪到这几个占位件的输出上 —— 那会造出一条永远不可能红的判据。
`timescale 1ns/1ps
module BUFG (input I, output O);
    assign O = I;                                   // 时钟缓冲：延迟与偏斜不建模
endmodule

module OBUFDS (input I, output O, output OB);
    assign O  =  I;
    assign OB = ~I;                                 // 差分输出：摆率/阻抗不建模
endmodule

module OSERDESE2 #(
    parameter DATA_WIDTH        = 8,
    parameter DATA_RATE_OQ      = "DDR",
    parameter DATA_RATE_TQ      = "SDR",
    parameter SERDES_MODE       = "MASTER",
    parameter SRVAL_OQ          = 0,
    parameter CLOCK_PROCESSING  = "FALSE"
) (
    output OQ, output [7:0] OFB, output TQ, output SHIFTOUT1, output SHIFTOUT2,
    output [3:0] STATUS,
    input T1, input T2, input T3, input T4,
    input [7:0] D,
    input TBYTEIN, input [1:0] TSELECT,
    input SHIFTIN1, input SHIFTIN2,
    input RST,
    input CLK, input CLKDIV
);
    // 串行化**完全不建模**：OQ 直接跟着 D[0] 走一个寄存器拍，OFB/TQ 给常数。
    reg q = 1'b0;
    assign OQ = q;
    assign OFB = 8'h0;  assign TQ = 1'b0;
    assign SHIFTOUT1 = 1'b0;  assign SHIFTOUT2 = 1'b0;  assign STATUS = 4'h0;
    always @(posedge CLKDIV) q <= D[0];
    initial $display("unisims_sim ⚠ OSERDESE2 是占位模型（不串行化）⇒ 判据只许读并行像素，不许读 DVI 引脚");
endmodule
