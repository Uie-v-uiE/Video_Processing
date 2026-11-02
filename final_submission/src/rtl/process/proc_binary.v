`timescale 1ns/1ps
// 级 4 阈值：亮度 >= threshold 出全白、否则全黑（pol 位反相）。放在滤波之后、形态学之前——形态学的定义
// 本来就是对面具图的操作。一级 1 拍，~bypass 时纯旁路。
// pol=0 亮于阈值算白（V7 的行为）；pol=1 暗于阈值算白（同一级的第二个算法，不额外占硬件）
module proc_binary (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,
    input  wire [7:0]  threshold,
    input  wire        pol,
    input  wire        de_in,
    input  wire [15:0] din,
    output reg         de_out,
    output reg  [15:0] dout
);
    wire [4:0] r5 = din[15:11];
    wire [5:0] g6 = din[10:5];
    wire [4:0] b5 = din[4:0];
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};
    wire [15:0] y16 = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;
    wire        cmp = (y16[15:8] >= threshold);
    wire bin = pol ? ~cmp : cmp;
    wire [15:0] bw = bin ? 16'hFFFF : 16'h0000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            de_out <= 1'b0;
            dout   <= 16'd0;
        end else begin
            de_out <= de_in;
            dout   <= bypass ? din : bw;
        end
    end
endmodule
