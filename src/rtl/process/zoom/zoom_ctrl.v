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
    output reg  [2:0]  zoom_code,     // V8-5：OSD 的"最近一档"编号（见下面的表）
    output reg         dir            // 0: 向缩小走(inv增) 1: 回到1.0x(inv减)
);
    // ---- OSD 用的 8 档倍率表（#58 合规做法：查表，不除）----
    // inv_scale 是 Q8 倒数尺度：scale = 256/inv ⇒ 想显示 "0.75x" 就得算 25600/inv，
    // 那是一条运行时非 2 幂除法 —— 在快域里就是 #58 那个 −5.014 ns 的组合除法器。
    // 所以这里只把 inv 与**相邻两档的中点**比大小（8 档 ⇒ 7 个常数比较，优先级链），
    // 结果寄存一拍再给 OSD ⇒ OSD 的 `chars[]` 那一片只多一个 3 bit 的 case 译码。
    // 档值：0=0.25 1=0.33 2=0.50 3=0.75 4=1.00 5=1.33 6=1.50 7=2.00
    // 中点取整：mid(1024,776)=900 mid(776,512)=644 mid(512,341)=427 mid(341,256)=299
    //           mid(256,192)=224 mid(192,171)=182 mid(171,128)=150
    reg [2:0] code_nxt;
    always @(*) begin
        if      (inv_scale >= 10'd900) code_nxt = 3'd0;
        else if (inv_scale >= 10'd644) code_nxt = 3'd1;
        else if (inv_scale >= 10'd427) code_nxt = 3'd2;
        else if (inv_scale >= 10'd299) code_nxt = 3'd3;
        else if (inv_scale >= 10'd224) code_nxt = 3'd4;
        else if (inv_scale >= 10'd182) code_nxt = 3'd5;
        else if (inv_scale >= 10'd150) code_nxt = 3'd6;
        else                     code_nxt = 3'd7;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inv_scale   <= INV_LO;
            dir         <= 1'b0;
            zoom_active <= 1'b0;
            zoom_code   <= 3'd4;                 // 1.00x：与 INV_LO=256 一致
        end else begin
            // 档位号只跟着**上一拍**的 inv_scale ⇒ 这一段不进 OSD 那条组合链（V7.9.4 的教训）。
            // 与 inv_scale 同一个块驱动：多驱动 net 会让综合扔掉逻辑那一侧，见 ISSUES #61。
            zoom_code   <= code_nxt;
            if (!enable) begin
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
    end
endmodule
