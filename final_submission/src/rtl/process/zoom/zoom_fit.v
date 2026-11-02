`timescale 1ns/1ps
// V9-2：按角度自动定缩放 —— "旋到哪个角度，就缩到刚好整个画面还在屏幕里"（用户 2026-09-25 提的那条）。
// 几何：视口 = 图像未旋转时的外框 IMAGE_W × IMAGE_H（`cx`/`cy` 就在这个框里量，1 源列 = 2 显示列）。图像以
// 显示倍率 s 旋转 θ 之后的外框是 W' = s·(W|cosθ| + H|sinθ|)、H' = s·(W|sinθ| + H|cosθ|)；要求 W'≤W 且 H'≤H
// ⇒（inv = 256/s，Q8）逐项写开就是下面那两条 inv_x = (W·C + H·S)/W、inv_y = (W·S + H·C)/H，取**较大者**就是
// "刚好装得下"，再留一点余量（见 fit_raw）。C/S 来自**与 zoom_mapper 同一张** Q8 三角表（256 = 1.0）⇒ 这里判
// 的"装得下"就是那条链真正画出来的框。输出的节拍与延迟见文件尾那条，别按"一拍"理解。
module zoom_fit #(
    parameter integer IMAGE_W = 512,
    parameter integer IMAGE_H = 300,
    parameter integer NSHIFT  = 20            // 倒数常数的定点位数
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [8:0]  angle,
    output reg  [9:0]  inv_fit                // Q8：256 = 1.0x，越大画面越小
);
    // 与 zoom_mapper 用的是**同一张**三角表 ⇒ 这里算出来的"装得下"判的就是那条链真正画出来的框。
    wire signed [9:0] sin_v, cos_v;
    sin_rom u_sin (.angle(angle), .value(sin_v));
    cos_rom u_cos (.angle(angle), .value(cos_v));
    // |·|：表里最大幅度是 256（=1.0），10 bit 无符号放得下，取反不会溢出。
    wire [9:0] C = cos_v[9] ? (~cos_v + 10'd1) : cos_v;
    wire [9:0] S = sin_v[9] ? (~sin_v + 10'd1) : sin_v;

    // ⚠ 运行时**没有除法器**（#58 那一课：100 MHz 域的组合除法器把 WNS 打到 −5.014）：/W 与 /H 折成"乘一个
    //   elaboration 常数 + 定长移位"，误差 ≤ 0.03 %，比 Q8 三角表本身 ±0.5 LSB 的量化误差还小。
    // round(2^NSHIFT / 边长)，elaboration 阶段算好 ⇒ 综合折成常量乘法（无除法器）
    localparam [NSHIFT-1:0] REC_W = ((1 << NSHIFT) + (IMAGE_W >> 1)) / IMAGE_W;
    localparam [NSHIFT-1:0] REC_H = ((1 << NSHIFT) + (IMAGE_H >> 1)) / IMAGE_H;

    wire [17:0] nx_c = IMAGE_W * C + IMAGE_H * S;     // ≤ (512+300)·256 = 207872 < 2^18
    wire [17:0] ny_c = IMAGE_W * S + IMAGE_H * C;
    // ⚠ 分两拍：第一拍只算分子（一次加法），第二拍做"乘常数 + 移位 + 取大 + 余量"。
    //   r60 实测 `angle → inv_fit` 一拍做完是 15 级、含两个 DSP48，slack 只剩 +1.843 ns
    //   （全设计第三差）；而这条链的输入一帧才变一次（自动旋转的步进钉在帧首），
    //   多一拍对屏上什么都看不见，换来的是一整段余量。
    //   ⇒ 拟合值现在**晚两拍**跟上新角度：仍然落在消隐里，与上面注释里那一拍同级的事实。
    reg [17:0] nx, ny;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin nx <= 18'd0; ny <= 18'd0; end
        else        begin nx <= nx_c;  ny <= ny_c;  end
    end
    wire [31:0] ix = (nx * REC_W) >> NSHIFT;          // 18×11 → 29 bit，一段乘法器就够
    wire [31:0] iy = (ny * REC_H) >> NSHIFT;
    wire [9:0]  imax = (ix > iy) ? ix[9:0] : iy[9:0];

    // 余量：Q8 三角表每一项最多差 0.5 LSB ⇒ inv 最大差 (W+H)/2/H ≈ 1.35，取 (imax>>8)+2 稳过它，
    // 而且在 0°/90°（表是精确的）只多缩 3/256 ≈ 1.2 %（屏上 6 个源列，看不见）。
    wire [10:0] fit_raw = {1'b0, imax} + (imax >> 8) + 11'd2;
    wire [10:0] fit_c   = (fit_raw > 11'd1023) ? 11'd1023 : fit_raw;
    // 输出是**比角度晚两拍**的寄存器值（上面那两级 always）：inv 与 angle 只错开 2 个像素周期，而不是错开
    // 一整帧。自动旋转时角度是在消隐里换的（angle_ctrl 用帧首翻转位），这两拍落在消隐里、屏上一个像素都看
    // 不见；手动按键若在帧中换角度也只有 2 列用旧倍率，同样是刚体平移级别的差别。**每拍都跟**，而不是"角度
    // 变了才装载"：后者在"角度没变、拟合刚被打开"那一支会留着旧值 ⇒ `zoom fit 1` 在 30° 按下去屏幕先不动。

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) inv_fit <= 10'd256;         // 上电角度就是 0 ⇒ 1.0x，与未开拟合时一致
        else        inv_fit <= fit_c[9:0];
    end
endmodule
