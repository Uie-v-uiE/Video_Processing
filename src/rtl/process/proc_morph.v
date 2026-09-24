`timescale 1ns/1ps
// 级 5：形态学 —— 3×3 腐蚀 / 膨胀。
//
// 为什么放在阈值之后：腐蚀/膨胀的定义是"邻域内全 1 才 1 / 有 1 就 1"，本来就是对面具图的操作。
// 放在灰度图上做 min/max 也能写，但那不是形态学，是另一种局部对比度。
//
// **结构逐条照 proc_box_blur 对齐**：同样的两条行缓存读法、同样的三拍 de 链（de_in→d1→d2→de_out）、
// 同样的"中心抽头 p11 做旁路"。理由不是省事：窗口级各自挑一种 de/数据对齐方式，混在一条链里
// 就会在切换效果的瞬间错一行。blur/sobel 用的是这个约定，新加的也用它。
// 这个约定本身还带着"窗口中心落在上一行"的既有错位 —— 那是 V7 就存在的性质，不是这次引入的，
// 独立记在 ISSUES #54；V8-4 要做"原图与处理图逐像素混合"，那条之前必须先修它。
//
// 掩码只存 1 bit/像素（亮度判定在输入处做一次）⇒ 两条掩码行缓存 = 512 bit × 2；
// 另加**一条** 16 bit 行缓存，只为旁路能还原原色（中心抽头只要上一行，所以一条就够）。
module proc_morph #(
    parameter H_ACTIVE = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [1:0]  mode,          // 0/3 旁路  1 腐蚀  2 膨胀
    input  wire [7:0]  threshold,
    input  wire        de_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [15:0] din,
    output reg         de_out,
    output reg  [15:0] dout
);
    // mode 3 是"开/闭运算"的位置，但那是**两遍**窗口（先腐蚀再膨胀），一遍做不出来，
    // 也不许偷偷当成其中一种 —— 所以显式当旁路，代价写在注释里而不是藏在 mux 里。
    wire by = (mode == 2'd0) || (mode == 2'd3);

    // 与 proc_binary 同一个亮度公式、同一对白/黑 ⇒ 级 4 → 级 5 视觉上只有形状在变
    wire [4:0] r5 = din[15:11];
    wire [5:0] g6 = din[10:5];
    wire [4:0] b5 = din[4:0];
    wire [7:0] r8 = {r5, r5[4:2]};
    wire [7:0] g8 = {g6, g6[5:4]};
    wire [7:0] b8 = {b5, b5[4:2]};
    wire [15:0] y16 = r8 * 8'd77 + g8 * 8'd150 + b8 * 8'd29;
    wire        bin = (y16[15:8] >= threshold);

    (* ram_style = "distributed" *) reg [0:H_ACTIVE-1] mb0;          // 掩码：上上行
    (* ram_style = "distributed" *) reg [0:H_ACTIVE-1] mb1;          // 掩码：上一行
    (* ram_style = "block" *)       reg [15:0] mc1 [0:H_ACTIVE-1];   // 原色：上一行（旁路用）

    always @(posedge clk) begin
        if (de_in) begin
            mb0[x_in] <= mb1[x_in];
            mb1[x_in] <= bin;
            mc1[x_in] <= din;
        end
    end
    wire        b00 = mb0[x_in];
    wire        b01 = mb1[x_in];
    wire [15:0] c01 = mc1[x_in];

    // 命名照 blur：第一维 0/1/2 = 上上/上/当前行，第二维 0/1/2 = 左/中/右
    reg m00, m01, m02, m10, m11, m12, m20, m21, m22;
    reg [15:0] p12, p11;
    reg dv_d1, dv_d2;
    reg [11:0] x_d1, y_d1;

    wire all1 = m00 & m01 & m02 & m10 & m11 & m12 & m20 & m21 & m22;
    wire any1 = m00 | m01 | m02 | m10 | m11 | m12 | m20 | m21 | m22;
    // 与 blur 唯一的差别：blur 只守卫首行，这里连**行首**也守卫（第一列的"左邻"是上一行末尾，
    // 对腐蚀是白啃一列、对膨胀是糊上一列）。台架因此只判内部区域，边界行为单独看 T9。
    wire border = (y_d1 == 12'd0) || (x_d1 == 12'd0);
    wire res = (mode == 2'd1) ? (border ? m11  : all1)
                              : (border ? m11  : any1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m00<=0; m01<=0; m02<=0; m10<=0; m11<=0; m12<=0; m20<=0; m21<=0; m22<=0;
            p12<=0; p11<=0; dv_d1<=0; dv_d2<=0; x_d1<=0; y_d1<=0; de_out<=0; dout<=0;
        end else begin
            if (de_in) begin
                m00<=m01; m01<=m02; m02<=b00;
                m10<=m11; m11<=m12; m12<=b01;
                m20<=m21; m21<=m22; m22<=bin;
                p12<=c01; p11<=p12;             // 原色中心抽头，与 blur 的 p11 同一个位置
            end
            dv_d1 <= de_in;
            x_d1  <= x_in;
            y_d1  <= y_in;
            dv_d2 <= dv_d1;
            de_out <= dv_d2;                    // 三拍，不是两拍 —— 见文件头与 ISSUES #54
            dout   <= by ? p11 : (res ? 16'hFFFF : 16'h0000);
        end
    end
endmodule
