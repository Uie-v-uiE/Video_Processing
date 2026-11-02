`timescale 1ns/1ps
// V9-1：把"缝"从**显示列**搬到**图像列** —— 分割线长在画面上，跟着旋转一起转（用户要的是"蓝线放在视频
// 中间、在视频的两端去转，而不是在整个屏幕上扫"）。今天 `split_display` 判的是"显示列 < 缝位"，所以那条线
// 永远竖直、贴的是**屏幕**的左右两端；`split_ctrl` 的 `follow` 位当时只改了扫描坐标系，线本身还是屏幕空间
// ⇒ "follow" 名不副实，本模块才是那半件事。判据换到图像列后 `sx == k` 是画面里的一条竖线，经逆映射画到屏
// 上就被同一个角度转过、同一个倍率缩过，端点也天然是画面的两端（画面外是 oob，蓝线在那里不画）。时钟域：像素域。
// ⚠ **对齐必须由流水线深度推出来，不许再抄字面量**（ISSUES #68 那一课）：见下面 `TAPS` 那一段。
module seam_src #(
    parameter integer TAPS = 18            // = 顶层的 MIX_D + 1 - 3，**由深度推出来，不许抄字面量**
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [11:0] sx,          // zoom_mapper 的图像列（与地址同一拍）
    input  wire [11:0] seam,        // 缝位，单位 = 图像列
    input  wire        marker_on,   // 1 = 画那条 2 列宽的标记线
    input  wire        raw_left,    // 1 = 缝左边给原图（swap 只翻这一位）
    output wire        take_orig,   // 已推到混色级：这一格给原图
    output wire        mark         // 已推到混色级：这一格是标记线（**画面内**由顶层再与像素那一位 oob 相与）
);
    // `sx` 站在 zoom_mapper 的输出那一拍（= 显示坐标之后第 3 拍），而混色级看的内容站在 `x_d[MIX_D]` 那一拍
    //（顶层把同一个抽头号交给了它）⇒ TAPS 就是"从 mapper 输出到混色级"那一段。晚/早几拍在这里只是把整条线
    // 刚体平移几列，**不会**再制造暗带 —— 暗带的根因是"标签与内容不同级"，这里两者是同一份流上的同一个位。
    // 分类在**源头**做（第 3 拍），结果只有一个位要跟着内容走 18 拍 —— 比把 12 位的 sx 打 18 级再比较，
    // 少 200 多个触发器，也少一条 12 位布线。
    wire in_band = (sx == seam) || (sx == (seam - 12'd1));   // 蓝线宽 = 2 个**图像列**
    // 蓝线只画在**画面内**：画面外是黑的，线伸出画面就是用户说的"在整个屏幕上扫"。
    // ⚠ #477 第二笔：这一条"画面内"不在这里判。这里吃的是 mapper 的**活几何** `oob`，而屏上那一格黑不黑
    //   由**与像素同环同尾巴**的那一位 `oob_out` 决定（#92 第一/三笔的成果）——两者在画面边沿可以差 1 格，
    //   实测旧写法在 45° 两臂留下 24 个"线画在黑底上"的像素（用户念的"上面出头 / 下面没到底"）。
    //   判据与填充必须是**同一个位**，否则线永远比画面短一截或长一截：门挪到顶层与 `oob_out` 相与。
    wire mark_n = marker_on && in_band;
    // 缝左侧给原图还是处理图，只由 swap 那一个位决定（与旧几何同一个语义）。
    wire orig_n = (sx < seam) ? raw_left : ~raw_left;

    reg [1:0] sh;                   // {mark, orig}，两级一起走同一条链 ⇒ 不会各自新旧
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) sh <= 2'b01;    // 复位：给"原图、不画线"，与旧代码 oob 时的观感一致
        else        sh <= {mark_n, orig_n};
    end
    generate
    if (TAPS == 0) begin : g_tap0
        assign mark      = sh[1];
        assign take_orig = sh[0];
    end else begin : g_taps
        reg [TAPS-1:0] dq;
        reg [TAPS-1:0] oq;
        // ⚠ 移位写法要能吃下 **TAPS = 1**（#477）。循环写法对任何 TAPS≥1 都合法。
        integer j;
        always @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                dq <= {TAPS{1'b0}};
                oq <= {TAPS{1'b1}};
            end else begin
                for (j = 0; j < TAPS; j = j + 1) begin
                    dq[j] <= (j == 0) ? sh[1] : dq[j-1];
                    oq[j] <= (j == 0) ? sh[0] : oq[j-1];
                end
            end
        end
        assign mark      = dq[TAPS-1];
        assign take_orig = oq[TAPS-1];
    end
    endgenerate
endmodule
