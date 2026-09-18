`timescale 1ns/1ps
// 无极缩放控制：原本尺寸(1.0x)为最大，向缩小方向循环再回到 1.0x。
// inv_scale Q8: 256=1.0x（最大），512=0.5x（最小，画面更小、四周黑边）。
// inv 越大 → 逆映射采样越“散”→ 显示画面越小。
module zoom_ctrl #(
    parameter [9:0] INV_LO = 10'd256,  // 1.0x 原始 = 最大
    parameter [9:0] INV_HI = 10'd512,  // 0.5x 最小
    parameter [9:0] STEP   = 10'd2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        frame_start,
    output reg  [9:0]  inv_scale,
    output reg         zoom_active,
    output reg         dir            // 0: 向缩小走(inv增) 1: 回到1.0x(inv减)
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inv_scale   <= INV_LO;
            dir         <= 1'b0;
            zoom_active <= 1'b0;
        end else if (!enable) begin
            inv_scale   <= INV_LO;
            dir         <= 1'b0;
            zoom_active <= 1'b0;
        end else if (frame_start) begin
            if (!dir) begin
                // inv 上升 → 画面缩小
                if (inv_scale + STEP >= INV_HI) begin
                    inv_scale <= INV_HI;
                    dir       <= 1'b1;
                end else begin
                    inv_scale <= inv_scale + STEP;
                end
            end else begin
                // inv 下降 → 回到原始大小
                if (inv_scale <= INV_LO + STEP) begin
                    inv_scale <= INV_LO;
                    dir       <= 1'b0;
                end else begin
                    inv_scale <= inv_scale - STEP;
                end
            end
            zoom_active <= 1'b1;
        end else begin
            zoom_active <= (inv_scale != INV_LO);
        end
    end
endmodule
