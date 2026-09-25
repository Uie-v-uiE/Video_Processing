`timescale 1ns/1ps
// Dual-pane: left original / right processed+zoomed.
// Display 1024x600, each pane 512 wide, source 512x300 with 2x vertical scale.
module split_display #(
    parameter PANE_W = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] x,
    input  wire [11:0] y,
    // ⚠ `x_sel` = **与两个像素抽头同一级**的列坐标（ISSUES #68）。
    //   以前本模块直接用 `x` 判"这一格属于左窗还是右窗"、也用它画那条 2 px 标记线，
    //   而顶层送进来的 `x` 是第 11 级标签，`orig_pix/proc_pix` 却是第 20 级的内容
    //   （3 拍打地址 + 1 拍读地址寄存 + 1 拍 BRAM + `u_pipe.LATENCY`=15）
    //   ⇒ 判定比内容旧 9 列 ⇒ 缝左边约 9 列里"标签说左窗、内容其实是右窗那一路(被强制清 0)"
    //   ⇒ 选中的是 0 ⇒ 一条近黑的竖带。这就是用户念的"缩放碰到分割线时周围出现颜色条"的第二个成分
    //   （第一个是故意画的蓝线，见下面 `marker`）。
    //   `x`/`y`/`de`/`hs`/`vs` 继续按原级数穿过输出寄存器 ⇒ **OSD 的位置一个像素都不动**；
    //   只有"选哪一路"与"标记线画在哪一列"跟着内容走（= 修好本应如此的东西）。
    input  wire [11:0] x_sel,
    input  wire        marker,           // 1 = 画那条 2 px 标记线（V8-4 起可关；关掉了 #56-2(a) 就没了）
    input  wire        de,
    input  wire        hs,
    input  wire        vs,
    input  wire [15:0] orig_pix,
    input  wire [15:0] proc_pix,
    input  wire [1:0]  angle_idx,
    input  wire        oob_l,
    input  wire        oob_r,
    output reg  [7:0]  r,
    output reg  [7:0]  g,
    output reg  [7:0]  b,
    output reg         de_out,
    output reg         hs_out,
    output reg         vs_out
);
    wire        left = (x_sel < PANE_W);
    wire        oob  = left ? oob_l : oob_r;
    wire [15:0] sel  = oob ? 16'h0000 : (left ? orig_pix : proc_pix);
    wire [4:0]  r5   = sel[15:11];
    wire [5:0]  g6   = sel[10:5];
    wire [4:0]  b5   = sel[4:0];
    wire        sep  = marker && ((x_sel == PANE_W-1) || (x_sel == PANE_W));

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r <= 0; g <= 0; b <= 0;
            de_out <= 0; hs_out <= 0; vs_out <= 0;
        end else begin
            de_out <= de;
            hs_out <= hs;
            vs_out <= vs;
            if (sep && de) begin
                r <= 8'h40; g <= 8'h40; b <= 8'hFF;
            end else begin
                r <= {r5, r5[4:2]};
                g <= {g6, g6[5:4]};
                b <= {b5, b5[4:2]};
            end
        end
    end
endmodule
