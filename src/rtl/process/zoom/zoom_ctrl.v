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
    input  wire [2:0]  zsel,            // V8-8：手动档号（见下面八档表）
    input  wire        manual,          // V8-8：1=停在手动档（呼吸被打断），0=自动呼吸
    input  wire        frame_start,
    output reg  [9:0]  inv_scale,
    output reg         zoom_active,
    output reg  [2:0]  zoom_code,     // V8-5：OSD 的"最近一档"编号（见下面的表）
    output reg         dir            // 0: 向缩小走(inv增) 1: 回到1.0x(inv减)
);
    // ---- V8-8：八档"用户能点出来的倍率"表（Q8 倒数尺度，纯常数，不做除法，#58）----
    // 档号与上面 OSD 那张表**同一个约定**：0=0.25 1=0.33 2=0.50 3=0.75 4=1.00 5=1.33 6=1.50 7=2.00。
    // 为什么两张表能互相对上：`zoom_code` 是拿 inv 与**相邻两档的中点**比大小得到的，
    // 所以表值代回自己那一档必然落在自己的区间里 —— 这条不是巧合，是台架判据
    // （`tb_v94_zoom_sel` 逐档验 `code(TBL[i]) == i`，任一边被改动都会红）。
    // 呼吸仍然只在 [INV_LO, INV_HI]（默认 1.0x…0.5x）里走；手动档允许到 2.0x/0.25x：
    // `zoom_mapper` 是**逆**映射，inv 变小只是采样窗收进画面内部（不越界），
    // inv 变大则四周填黑 —— 两种都不需要动 mapper。
    function [9:0] tbl;
        input [2:0] i;
        begin
            case (i)
                3'd0: tbl = 10'd1023;   // 0.25x —— **不是 1024**：inv_scale 只有 10 bit（Q8 的天花板
                                        // 就是 1023 ⇒ 1024 会回绕成 0，画面上变成"无限大"而不是 0.25x）。
                                        // 1023 对应 0.2502x，与档名差 0.02 %，台架按 10 bit 的边界钉住。
                3'd1: tbl = 10'd776;    // 0.33x
                3'd2: tbl = 10'd512;    // 0.50x
                3'd3: tbl = 10'd341;    // 0.75x
                3'd4: tbl = 10'd256;    // 1.00x
                3'd5: tbl = 10'd192;    // 1.33x
                3'd6: tbl = 10'd171;    // 1.50x
                default: tbl = 10'd128; // 2.00x
            endcase
        end
    endfunction
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
            end else if (manual && frame_start) begin
                // 手动档：**与呼吸同一个节拍，只在帧首换** ⇒ 一帧之内不会半屏新一档半屏旧一档。
                // `dir` 故意不动：从手动切回自动时，从当前 inv 继续朝原方向走（不跳档）。
                inv_scale   <= tbl(zsel);
                zoom_active <= (tbl(zsel) != INV_LO);
            end else if (frame_start) begin
                // 手动档可以把画面停在呼吸带**之外**（2.0x 在下方、0.25x 在上方）。
                // 切回自动时不许瞬移：原来 `!dir` 那一支在 inv 已经大于 INV_HI 时会写成
                // `inv <= INV_HI`，于是 1023 → 512 一帧跳掉半幅 —— 用户看到的就是"画面弹一下"。
                // 现在改成**朝带回里走**（每帧一步），进带之后原有逻辑接管，方向交给 dir。
                if (inv_scale > INV_HI) begin
                    inv_scale <= inv_scale - STEP;
                    dir       <= 1'b1;
                end else if (!dir) begin
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
