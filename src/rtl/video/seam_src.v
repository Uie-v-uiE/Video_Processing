`timescale 1ns/1ps
// V9-1：把"缝"从**显示列**搬到**图像列** —— 分割线长在画面上，跟着旋转一起转。
//
// 用户 2026-09-25 的原话：「将蓝线放在视频的中间，在视频的两端去转，而不是在整个屏幕上
// 左右扫。蓝线要能跟着视频去转。」今天 `split_display` 判的是"显示列 < 缝位"，所以那条线
// 永远是竖直的、贴的是**屏幕**的左右两端；`split_ctrl` 的 `follow` 位当时只改了扫描坐标系
// （端点按源宽量），线本身还是屏幕空间的 ⇒ "follow" 名不副实。本模块才是那半件事。
//
// 判据换到图像列之后：`sx == k` 是**画面里**的一条竖线，经逆映射画到屏上就是一条被同一个
// 角度转过、被同一个倍率缩过的线 —— 它天然跟着画面转，端点也天然是画面的两端（画面外的
// 那些像素是 oob，蓝线在那里不画，见下面 `mark` 里的 `~oob`）。
//
// ⚠ **对齐必须由流水线深度推出来，不许再抄字面量**（ISSUES #68 那一课）：
//   `sx` 站在 zoom_mapper 的输出那一拍（= 显示坐标之后第 3 拍），而混色级看的内容站在
//   `x_d[MIX_D]` 那一拍（顶层把同一个抽头号交给了它）。所以本模块的 `TAPS` 是
//   "从 mapper 输出到混色级"的那一段，由顶层用 `MIX_D + 1 - 3` 算出来传进来。
//   晚/早几拍在这里只是把整条线平移几列（线是刚体平移），**不会**再制造暗带 ——
//   暗带的根因是"标签与内容不同级"，这里两者是同一份流上的同一个位。
module seam_src #(
    parameter integer TAPS = 18            // = 顶层的 MIX_D + 1 - 3
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] sx,          // zoom_mapper 的图像列（与地址同一拍）
    input  wire        oob,         // 同一拍的"画面外"
    input  wire [11:0] seam,        // 缝位，单位 = 图像列
    input  wire        marker_on,   // 1 = 画那条 2 列宽的标记线
    input  wire        raw_left,    // 1 = 缝左边给原图（swap 只翻这一位）
    output wire        take_orig,   // 已推到混色级：这一格给原图
    output wire        mark         // 已推到混色级：这一格画蓝线
);
    // 分类在**源头**做（第 3 拍），做的结果只有一个位要跟着内容走 18 拍 ——
    // 比把 12 位的 sx 打 18 级再到这里比较，少 200 多个触发器，也少一条 12 位布线。
    wire in_band = (sx == seam) || (sx == (seam - 12'd1));   // 蓝线宽 = 2 个**图像列**
    // 蓝线只画在**画面内**（画面外是黑的，线上伸出画面就是用户说的"在整个屏幕上扫"）。
    wire mark_n = marker_on && in_band && !oob;
    // 缝左侧给原图还是处理图，只由 swap 那一个位决定（与旧几何同一个语义）。
    wire orig_n = (sx < seam) ? raw_left : ~raw_left;

    reg [1:0] sh;                   // {mark, orig}，两级一起走同一条链 ⇒ 不会各自新旧
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sh <= 2'b01;    // 复位：给"原图、不画线"，与旧代码 oob 时的观感一致
        else        sh <= {mark_n, orig_n};
    end
    reg [TAPS-1:0] dq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dq <= {TAPS{1'b0}};
        else        dq <= {dq[TAPS-2:0], sh[1]};
    end
    reg [TAPS-1:0] oq;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) oq <= {TAPS{1'b1}};
        else        oq <= {oq[TAPS-2:0], sh[0]};
    end
    assign mark      = dq[TAPS-1];
    assign take_orig = oq[TAPS-1];
endmodule
