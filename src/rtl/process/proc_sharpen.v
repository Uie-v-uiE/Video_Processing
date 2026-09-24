`timescale 1ns/1ps
// 级 2 的第二个算法：3×3 锐化（卷积核 [0,-1,0 ; -1,5,-1 ; 0,-1,0]，四邻是上/下/左/右）。
//
// 与 proc_box_blur 是**同一级的两个选项**，不是串联：先模糊再锐化几乎等于什么都没做，
// 所以控制字里这两个占同一个 2 bit 字段。
//
// 三个通道分开算，**先比较再相减**：Verilog 的无符号减法会回绕，直接 `a-b` 然后判负是错的
// （表现是"暗边变成一圈亮边"）。5×中心 与 四邻之和 都是无符号，比完大小再夹到 [0, 满量程]。
//
// 延迟与 proc_box_blur 一致（固定 2 拍，与 bypass 无关）—— 整条链的总延迟见 proc_pipeline_lat.vh。
module proc_sharpen #(
    parameter H_ACTIVE = 512
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bypass,
    input  wire        de_in,
    input  wire [11:0] x_in,
    input  wire [11:0] y_in,
    input  wire [15:0] din,
    output reg         de_out,
    output reg  [15:0] dout
);
    (* ram_style = "block" *) reg [15:0] lb0 [0:H_ACTIVE-1];
    (* ram_style = "block" *) reg [15:0] lb1 [0:H_ACTIVE-1];

    reg [15:0] p00, p01, p02, p10, p11, p12, p20, p21, p22;
    reg        de_d1, de_d2;
    reg [11:0] x_d1, y_d1;

    always @(posedge clk) begin
        if (de_in) begin
            lb0[x_in] <= lb1[x_in];
            lb1[x_in] <= din;
        end
    end
    wire [15:0] up2 = lb0[x_in];           // 上上行
    wire [15:0] up1 = lb1[x_in];           // 上一行

    // R/B 5 bit，G 6 bit；中心 ×4 + 中心 = ×5，四邻直接相加（≤ 4×满量程）
    // 抽头约定与 proc_box_blur 一模一样：**移位之前**的 p00..p22 就是以 p11 为中心的 3×3，
    // 组合逻辑算完、下一拍寄存输出，所以四邻取 p01(上)/p21(下)/p10(左)/p12(右)。
    // 顺手用 up2/up1（还没移位进来的新值）会把整幅图错一行 —— 这是 blur 台架早就钉过的方向。
    wire [8:0] r_c = {p11[15:11], 2'b00} + {4'b0000, p11[15:11]};
    wire [8:0] r_n = {4'b0000, p01[15:11]} + {4'b0000, p21[15:11]}
                   + {4'b0000, p10[15:11]} + {4'b0000, p12[15:11]};
    wire [9:0] g_c = {p11[10:5], 2'b00} + {4'b0000, p11[10:5]};
    wire [9:0] g_n = {4'b0000, p01[10:5]} + {4'b0000, p21[10:5]}
                   + {4'b0000, p10[10:5]} + {4'b0000, p12[10:5]};
    wire [8:0] b_c = {p11[4:0], 2'b00} + {4'b0000, p11[4:0]};
    wire [8:0] b_n = {4'b0000, p01[4:0]} + {4'b0000, p21[4:0]}
                   + {4'b0000, p10[4:0]} + {4'b0000, p12[4:0]};

    wire [8:0] r_d = (r_c > r_n) ? (r_c - r_n) : 9'd0;
    wire [9:0] g_d = (g_c > g_n) ? (g_c - g_n) : 10'd0;
    wire [8:0] b_d = (b_c > b_n) ? (b_c - b_n) : 9'd0;
    wire [4:0] r_o = (r_d > 9'd31)  ? 5'd31 : r_d[4:0];
    wire [5:0] g_o = (g_d > 10'd63) ? 6'd63 : g_d[5:0];
    wire [4:0] b_o = (b_d > 9'd31)  ? 5'd31 : b_d[4:0];
    wire [15:0] sharp = {r_o, g_o, b_o};

    // 首行的行缓存是空的、行首的"左邻"是上一行末尾 —— 与 proc_morph 同一套处理：只取中心
    // （变量一开始叫 `edge`，那是 Verilog 保留字：综合报 Synth 8-10307 后
    //   接着把下一行误判成"`res` 是未知类型"，第一个错误才是真的）
    wire border = (y_d1 == 12'd0) || (x_d1 == 12'd0);


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0; p20<=0; p21<=0; p22<=0;
            de_d1<=0; de_d2<=0; x_d1<=0; y_d1<=0; de_out<=0; dout<=0;
        end else begin
            if (de_in) begin
                p00<=p01; p01<=p02; p02<=up2;
                p10<=p11; p11<=p12; p12<=up1;
                p20<=p21; p21<=p22; p22<=din;
            end
            de_d1 <= de_in;
            x_d1  <= x_in;
            y_d1  <= y_in;
            de_d2 <= de_d1;
            de_out <= de_d2;
            // 旁路/边界取 p11（窗口中心抽头）—— 与 proc_box_blur / proc_sobel / proc_morph 同一个约定。
            // 本级单独做到"de 与数据自洽"反而更糟：混用约定会让"开关某一级"时画面跳一行。
            // 窗口级本身的行列错位是独立问题，记在 ISSUES #54，不在这里半修。
            dout   <= (bypass || border) ? p11 : sharp;   // 中心抽头，与 blur 同约定
        end
    end
endmodule
